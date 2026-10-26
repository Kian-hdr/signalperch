import Foundation

enum ReorderSlots {
    static func destination(origin: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return 0 }
        return min(max(Int((CGFloat(origin) + translation / pitch).rounded()), 0), count - 1)
    }
    static func slot(for index: Int, origin: Int, destination: Int, dragging: Bool) -> Int {
        guard dragging, index != origin else { return index }
        if origin < destination, index > origin, index <= destination { return index - 1 }
        if origin > destination, index < origin, index >= destination { return index + 1 }
        return index
    }
}
