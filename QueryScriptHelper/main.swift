/**
 @name: 查询脚本辅助进程
 @Descripttion: 在独立 JavaScriptCore 上下文中转换请求及额度结果。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:56:06
 @LastEditTime: 2026-09-08 14:56:06
 @FilePath: QueryScriptHelper/main.swift
 */
import Foundation
import JavaScriptCore

func emit(_ object: Any) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object) else { exit(2) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}

guard let line = readLine(), let input = line.data(using: .utf8),
      let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      var code = payload["code"] as? String,
      let variables = payload["variables"] as? [String: String],
      let context = JSContext() else { exit(2) }

// Legacy templates embed variables inside JS strings. Unicode escaping preserves
// their contents without allowing a credential to become executable source.
for (key, value) in variables {
    let escaped = value.utf16.map { String(format: "\\u%04x", $0) }.joined()
    code = code.replacingOccurrences(of: "{{\(key)}}", with: escaped)
    context.setObject(value, forKeyedSubscript: key as NSString)
}
context.setObject(variables, forKeyedSubscript: "variables" as NSString)
guard let config = context.evaluateScript(code), context.exception == nil,
      let request = config.forProperty("request")?.toDictionary(),
      let extractor = config.forProperty("extractor"), !extractor.isUndefined else { exit(2) }
emit(request)
guard let responseLine = readLine(), let responseData = responseLine.data(using: .utf8),
      let response = try? JSONSerialization.jsonObject(with: responseData, options: .fragmentsAllowed),
      let result = extractor.call(withArguments: [response]), context.exception == nil,
      let object = result.toObject() else { exit(2) }
emit(["result": object])
