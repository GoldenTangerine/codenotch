/**
 @name: 查询脚本运行器
 @Descripttion: 管理可取消的脚本进程并执行隔离的 HTTP 查询。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: Sources/Providers/QueryScriptRunner.swift
 */
import Foundation
import Darwin

enum QueryDeadline {
    static func run<Value>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw QueryError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

final class QueryHTTPClient: NSObject, URLSessionTaskDelegate {
    static let shared = QueryHTTPClient()
    private var session: URLSession!

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward supplied credentials to a redirected endpoint.
        completionHandler(nil)
    }

    func data(for request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageProviderError.badResponse(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageProviderError.needsAuth }
        if http.statusCode == 429 {
            let value = http.value(forHTTPHeaderField: "Retry-After") ?? ""
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let delay = Double(value) ?? formatter.date(from: value)?.timeIntervalSinceNow ?? 60
            throw UsageProviderError.rateLimited(retryAfter: max(1, delay))
        }
        guard (200..<300).contains(http.statusCode) else { throw UsageProviderError.badResponse(status: http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw QueryError.invalid("Response exceeds 2 MB.") }
            data.append(byte)
        }
        return data
    }

    static func request(_ object: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        guard let raw = object["url"] as? String, let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else {
            throw QueryError.invalid("Enter a valid HTTP or HTTPS query URL.")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = (object["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].contains(request.httpMethod ?? "") else {
            throw QueryError.invalid("Unsupported HTTP method.")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let headers = object["headers"] as? [String: String] {
            for (name, value) in headers {
                guard !name.contains(where: { $0.isNewline }), !value.contains(where: { $0.isNewline }) else {
                    throw QueryError.invalid("Headers cannot contain newlines.")
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        if let body = object["body"], !(body is NSNull) {
            if let text = body as? String { request.httpBody = Data(text.utf8) }
            else {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .fragmentsAllowed)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        return request
    }
}

final class QueryScriptRunner: @unchecked Sendable {
    private let executableURL: URL?
    private let fetch: @Sendable (URLRequest) async throws -> Data
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var readBuffer = Data()
    private let lock = NSLock()
    private var stopped = false

    init(executableURL: URL? = nil,
         fetch: @escaping @Sendable (URLRequest) async throws -> Data = { try await QueryHTTPClient.shared.data(for: $0) }) {
        self.executableURL = executableURL
        self.fetch = fetch
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private func launch() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        guard let executable = executableURL ?? Bundle.main.url(forAuxiliaryExecutable: "QueryScriptHelper") else {
            throw QueryError.invalid("Query script helper is missing. Reinstall Codenotch.")
        }
        process.executableURL = executable
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = [:]
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
    }

    private func send(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed)
        try input.fileHandleForWriting.write(contentsOf: data + Data([10]))
    }

    private func receive() throws -> [String: Any] {
        while readBuffer.firstIndex(of: 10) == nil {
            // FileHandle's bulk read can wait for a full buffer. A pipe peer
            // waiting for our response needs a single POSIX read of available bytes.
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(output.fileHandleForReading.fileDescriptor, $0.baseAddress, $0.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw QueryError.script
            }
            if count == 0 { break }
            readBuffer.append(contentsOf: bytes.prefix(count))
            guard readBuffer.count <= 2_000_000 else { throw QueryError.invalid("Script output exceeds 2 MB.") }
        }
        let end = readBuffer.firstIndex(of: 10) ?? readBuffer.endIndex
        let data = Data(readBuffer[..<end])
        readBuffer = end < readBuffer.endIndex ? Data(readBuffer[(end + 1)...]) : Data()
        lock.lock()
        let wasStopped = stopped
        lock.unlock()
        if wasStopped { throw QueryError.timeout }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QueryError.script }
        return object
    }

    func run(code: String, variables: [String: String], timeout: Double) async throws -> [LimitWindow] {
        let task = Task.detached { [self] in
            defer {
                stop()
                if process.processIdentifier != 0 { process.waitUntilExit() }
                try? input.fileHandleForWriting.close()
                try? output.fileHandleForReading.close()
            }
            try launch()
            try send(["code": code, "variables": variables])
            let request = try QueryHTTPClient.request(receive(), timeout: timeout)
            let data = try await fetch(request)
            let response = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            try send(response)
            guard let result = try receive()["result"] else { throw QueryError.script }
            return try QueryResultParser.windows(result)
        }
        return try await QueryDeadline.run(seconds: timeout) {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await task.value
            } onCancel: {
                task.cancel()
                self.stop()
            }
        }
    }
}

enum QueryResultParser {
    static func windows(_ result: Any) throws -> [LimitWindow] {
        let items = (result as? [Any]) ?? [result]
        guard !items.isEmpty, items.count <= 64 else { throw QueryError.invalid("Return between 1 and 64 quota items.") }
        var ids = Set<String>()
        return try items.enumerated().map { index, item in
            guard let item = item as? [String: Any] else { throw QueryError.invalid("Quota items must be objects.") }
            let id = item["key"] as? String ?? "item-\(index)"
            guard !id.isEmpty, ids.insert(id).inserted else { throw QueryError.invalid("Quota keys must be unique.") }
            if item["isValid"] as? Bool == false {
                throw QueryError.invalid("The query returned an invalid quota item.")
            }
            func number(_ key: String) throws -> Double? {
                guard let raw = item[key], !(raw is NSNull) else { return nil }
                guard !(raw is NSNumber && CFGetTypeID(raw as! NSNumber) == CFBooleanGetTypeID()),
                      let value = Double(String(describing: raw)), value.isFinite else {
                    throw QueryError.invalid("Quota values must be finite numbers.")
                }
                return value
            }
            let remaining = try number("remaining")
            let used = try number("used")
            let total = try number("total")
            guard total == nil || total! >= 0, used == nil || used! >= 0 else {
                throw QueryError.invalid("Used and total quota cannot be negative.")
            }
            let unlimited = item["unlimited"] as? Bool ?? false
            guard remaining != nil || used != nil || total != nil || unlimited else {
                throw QueryError.invalid("Quota item has no used, total or remaining value.")
            }
            let effectiveUsed = used ?? total.flatMap { total in remaining.map { total - $0 } }
            let effectiveRemaining = remaining ?? total.flatMap { total in used.map { total - $0 } }
            let fraction = !unlimited && (total ?? 0) > 0 ? effectiveUsed.map { max(0, $0 / total!) } : nil
            guard fraction == nil || (fraction!.isFinite && fraction! < 1e12),
                  effectiveRemaining == nil || effectiveRemaining!.isFinite else {
                throw QueryError.invalid("Quota value exceeds the supported range.")
            }
            return LimitWindow(id: id, label: String((item["label"] as? String ?? id).prefix(120)),
                usedFraction: fraction, resetsAt: parseDate(item["nextReset"]),
                quantity: QuotaQuantity(remaining: effectiveRemaining, used: effectiveUsed, total: total,
                    unit: String((item["unit"] as? String ?? "").prefix(16)), unlimited: unlimited))
        }
    }

    static func parseDate(_ value: Any?) -> Date? {
        if let value, let number = Double(String(describing: value)), number.isFinite, number > 0 {
            return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
