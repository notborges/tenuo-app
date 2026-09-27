import Foundation

enum TrackpadGesture: String, CaseIterable, Codable, Sendable {
    case up, down, left, right

    var title: String { "Swipe \(rawValue)" }
    var symbol: String { "arrow.\(rawValue)" }
}

struct GestureAssignment {
    let layerID: UUID
    let mapping: LayerMapping
    let consumedFlags: EventFlags
}

/// Owns one scrolling sequence, including its trailing momentum.
struct TrackpadSequence {
    enum Phase { case began, changed, ended, cancelled, momentum, momentumEnded }
    struct Result {
        let suppress: Bool
        var gesture: TrackpadGesture? = nil
        var replayBuffered = false
    }

    private(set) var isCaptured = false
    private(set) var isTouching = false
    private var fired = false
    private var x = 0.0
    private var y = 0.0
    private var lastTime = 0.0
    private var mappedGestures = Set<TrackpadGesture>()

    var isPending: Bool { isCaptured && !fired }

    func isTouching(at time: Double) -> Bool { isCaptured && isTouching && time - lastTime <= 2 }

    mutating func reset() { self = Self() }

    // A cancelled mapping must not fire or replay into a different app/context.
    mutating func cancelRecognition() { fired = true }

    mutating func passThrough() -> Result {
        isCaptured = false
        fired = true
        return Result(suppress: false, replayBuffered: true)
    }

    mutating func handle(
        phase: Phase, x dx: Double, y dy: Double, time: Double, canCapture: Bool,
        isDirectionInvertedFromDevice: Bool = false,
        mappedGestures: Set<TrackpadGesture> = Set(TrackpadGesture.allCases)
    ) -> Result {
        if time - lastTime > 2 { reset() }
        lastTime = time
        if phase == .began {
            isCaptured = canCapture && !mappedGestures.isEmpty
            self.mappedGestures = mappedGestures
            isTouching = true
            fired = false
            x = 0
            y = 0
        }
        let suppress = isCaptured
        if phase == .ended || phase == .cancelled || phase == .momentumEnded {
            isTouching = false
            if isPending { return passThrough() }
            if phase != .ended { isCaptured = false }
            return Result(suppress: suppress)
        }
        if phase == .momentum, isPending { return passThrough() }
        guard isCaptured, isTouching, !fired,
            phase == .began || phase == .changed
        else { return Result(suppress: suppress) }
        // Undo Natural Scrolling, then orient X toward the right and Y upward.
        let sign = isDirectionInvertedFromDevice ? -1.0 : 1.0
        x -= dx * sign
        y += dy * sign
        // A clear direction avoids firing on resting fingers or diagonal jitter.
        guard max(abs(x), abs(y)) >= 32,
            max(abs(x), abs(y)) >= min(abs(x), abs(y)) * 1.35
        else {
            return Result(suppress: true)
        }
        fired = true
        let gesture: TrackpadGesture =
            abs(x) > abs(y)
            ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
        if !self.mappedGestures.contains(gesture) { return passThrough() }
        return Result(suppress: true, gesture: gesture)
    }
}
