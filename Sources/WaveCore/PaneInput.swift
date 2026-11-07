/// Turns the bytes tmux sends the waveform pane into events: Tab from the
/// Option-Tab binding, and clicks reported as SGR mouse sequences
/// (`ESC [ < button ; column ; row M`).
public struct PaneInput {
    public enum Event: Equatable, Sendable {
        case tab
        /// A left-button press at a 1-based column and row of the pane.
        case click(column: Int, row: Int)
        /// Wheel or trackpad scroll at a row: -1 up, +1 down.
        case scroll(Int, row: Int)
    }

    /// Asks the terminal (tmux) for button presses in SGR form.
    public static let enableMouse = "\u{1B}[?1000h\u{1B}[?1006h"
    public static let disableMouse = "\u{1B}[?1006l\u{1B}[?1000l"

    private var pending: [UInt8] = []

    public init() {}

    /// Events in `bytes`. A sequence cut off at the end waits for the next call.
    public mutating func feed(_ bytes: [UInt8]) -> [Event] {
        pending += bytes
        var events: [Event] = []
        var index = 0
        while index < pending.count {
            let byte = pending[index]
            if byte == 9 {
                events.append(.tab)
                index += 1
            } else if byte == 0x1B {
                guard let (event, length) = Self.mouse(pending[index...]) else { break }
                if let event { events.append(event) }
                index += length
            } else {
                index += 1
            }
        }
        pending.removeFirst(index)
        if pending.count > 32 { pending.removeAll() }  // never a valid sequence
        return events
    }

    /// The event (nil if ignored) and bytes consumed, or nil if incomplete.
    private static func mouse(_ bytes: ArraySlice<UInt8>) -> (Event?, Int)? {
        let prefix: [UInt8] = [0x1B, UInt8(ascii: "["), UInt8(ascii: "<")]
        let start = bytes.startIndex
        for (offset, expected) in prefix.enumerated() {
            guard start + offset < bytes.endIndex else { return nil }
            guard bytes[start + offset] == expected else { return (nil, 1) }
        }
        guard let end = bytes[(start + 3)...].firstIndex(where: { $0 == UInt8(ascii: "M") || $0 == UInt8(ascii: "m") })
        else { return nil }
        let fields = String(decoding: bytes[(start + 3)..<end], as: UTF8.self).split(separator: ";").map { Int($0) }
        let length = end - start + 1
        guard fields.count == 3, let button = fields[0], let column = fields[1], let row = fields[2] else {
            return (nil, length)
        }
        guard bytes[end] == UInt8(ascii: "M") else { return (nil, length) }
        switch button {
        case 0: return (.click(column: column, row: row), length)  // left press, no modifiers or motion
        case 64: return (.scroll(-1, row: row), length)
        case 65: return (.scroll(1, row: row), length)
        default: return (nil, length)
        }
    }
}
