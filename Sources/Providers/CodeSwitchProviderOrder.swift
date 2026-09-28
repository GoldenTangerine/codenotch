/**
 @name: 联动供应商排序
 @Descripttion: 在设置与刘海之间共享本地顺序并保留暂时离线的供应商位置。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-10 20:59:03
 @LastEditTime: 2026-09-10 20:59:03
 @FilePath: Sources/Providers/CodeSwitchProviderOrder.swift
 */
import Foundation

enum CodeSwitchProviderOrder {
    enum Placement {
        case before, after

        static func at(y: CGFloat, height: CGFloat) -> Self {
            y < height / 2 ? .before : .after
        }
    }

    static func normalized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { $0.hasPrefix("code-switch:") && seen.insert($0).inserted }
    }

    static func arrange<T>(_ items: [T], by order: [String], id: (T) -> String,
                           name: (T) -> String, platform: (T) -> String) -> [T] {
        let ranks = Dictionary(normalized(order).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.sorted {
            let left = ranks[id($0), default: .max], right = ranks[id($1), default: .max]
            if left != right { return left < right }
            let names = name($0).localizedStandardCompare(name($1))
            if names != .orderedSame { return names == .orderedAscending }
            let platforms = platform($0).localizedStandardCompare(platform($1))
            if platforms != .orderedSame { return platforms == .orderedAscending }
            return id($0) < id($1)
        }
    }

    static func moving(_ id: String, onto target: String, placement: Placement,
                       visible: [String], remembered: [String]) -> [String]? {
        var visible = normalized(visible)
        guard id != target, let from = visible.firstIndex(of: id), let to = visible.firstIndex(of: target) else { return nil }
        let insertion = to + (placement == .after ? 1 : 0)
        let destination = insertion - (from < insertion ? 1 : 0)
        guard destination != from else { return nil }
        let moved = visible.remove(at: from)
        visible.insert(moved, at: destination)
        let visibleIDs = Set(visible)
        var reordered = visible.makeIterator()
        // Replace only visible slots, leaving absent providers in their saved positions.
        return normalized(remembered + visible).map { visibleIDs.contains($0) ? reordered.next()! : $0 }
    }

    static func apply(_ order: [String], to snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let linked = snapshots.filter { $0.linked != nil }
        var sorted = arrange(linked, by: order, id: \.id, name: \.displayName,
                             platform: { $0.linked?.platform ?? "" }).makeIterator()
        return snapshots.map { $0.linked != nil ? sorted.next()! : $0 }
    }
}
