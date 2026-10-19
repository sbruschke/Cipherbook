import Foundation

/// Reading a slide on the pile as a page turn: the top page leaves sideways and goes to the bottom.
public enum PageTurn {
    /// Points of travel after which a drag counts as a turn.
    public static let dragThreshold = 90.0
    /// Where the finger would end up if it kept going (UIKit's predicted end): a quick flick counts too.
    public static let flickThreshold = 180.0

    /// +1 for a slide to the right, -1 to the left, nil when it was too small or mostly vertical.
    public static func direction(dx: Double, dy: Double, predictedDx: Double) -> Int? {
        guard abs(dx) > abs(dy) else { return nil }
        let travelled = abs(dx) >= dragThreshold
        let flicked = abs(predictedDx) >= flickThreshold && abs(dx) >= 20 && (dx > 0) == (predictedDx > 0)
        guard travelled || flicked else { return nil }
        return dx > 0 ? 1 : -1
    }
}
