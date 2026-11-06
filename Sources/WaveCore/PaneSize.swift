import Foundation

/// Size of the waveform pane. The window gets the rows it can spare and
/// the shell keeps enough width to stay usable.
public struct PaneSize: Equatable, Sendable {
    public static let standard = PaneSize(cols: 48, rows: 12)

    private static let colsKey = "paneCols"
    private static let rowsKey = "paneRows"
    private static let colsRange = 12...120
    private static let rowsRange = 3...40
    private static let shellCols = 40

    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }

    /// Reads `60x16`. Nil when either side is out of range.
    public init?(spec: String) {
        let sides = spec.split(separator: "x", omittingEmptySubsequences: false).map { Int($0) }
        guard sides.count == 2, let cols = sides[0], let rows = sides[1],
              Self.colsRange.contains(cols), Self.rowsRange.contains(rows) else { return nil }
        self.init(cols: cols, rows: rows)
    }

    public static func stored(in store: UserDefaults) -> PaneSize {
        let size = PaneSize(cols: store.integer(forKey: colsKey), rows: store.integer(forKey: rowsKey))
        return colsRange.contains(size.cols) && rowsRange.contains(size.rows) ? size : .standard
    }

    public func save(to store: UserDefaults) {
        store.set(cols, forKey: Self.colsKey)
        store.set(rows, forKey: Self.rowsKey)
    }

    /// Columns to use in a window this wide, or nil when there is no room.
    public func columns(inWindow window: Int) -> Int? {
        let available = min(cols, window - Self.shellCols)
        return available >= Self.colsRange.lowerBound ? available : nil
    }
}
