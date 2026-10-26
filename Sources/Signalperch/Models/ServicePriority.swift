import Foundation

enum ServicePriority {
    static func normalized(_ saved: [String]) -> [String] {
        let known = Provider.all.map(\.id)
        var seen = Set<String>()
        return (saved + known).filter { known.contains($0) && seen.insert($0).inserted }
    }
    static func reordered(_ ids: [String], moving sources: [String], before destination: String?) -> [String] {
        let movedIDs = Set(sources)
        guard destination.map({ !movedIDs.contains($0) }) ?? true else { return ids }
        let moved = ids.filter { movedIDs.contains($0) }
        guard !moved.isEmpty else { return ids }
        var remaining = ids.filter { !movedIDs.contains($0) }
        let insertion = destination.flatMap { remaining.firstIndex(of: $0) } ?? remaining.endIndex
        remaining.insert(contentsOf: moved, at: insertion)
        return remaining
    }
    static func moved(_ ids: [String], from offsets: IndexSet, to destination: Int) -> [String] {
        guard destination >= 0, destination <= ids.count, offsets.allSatisfy({ ids.indices.contains($0) }) else { return ids }
        let items = offsets.map { ids[$0] }
        var remaining = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let adjusted = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: items, at: adjusted)
        return remaining
    }
    static func firstEnabled(in order: [String], enabled: Set<String>) -> String? {
        normalized(order).first { enabled.contains($0) }
    }
}
