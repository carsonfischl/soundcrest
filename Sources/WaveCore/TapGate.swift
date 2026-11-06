/// Decides whether the audio tap should run. An open tap keeps Core Audio
/// holding a sleep assertion, so it should run only while something plays. The
/// hold keeps it open across gaps such as track changes.
public struct TapGate {
    private let hold: Double
    private var closesAt = -Double.infinity

    public init(hold: Double) { self.hold = hold }

    /// `now` is in seconds, on any clock that only moves forward.
    public mutating func update(outputActive: Bool, now: Double) -> Bool {
        if outputActive { closesAt = now + hold }
        return now < closesAt
    }
}
