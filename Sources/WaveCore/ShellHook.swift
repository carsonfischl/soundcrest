import Foundation

/// The `.zshrc` block that opens new Terminal.app windows with the pane. It has
/// to stay safe at every shell start, so anything unexpected means a plain shell.
public enum ShellHook {
    private static let begin = "# >>> soundcrest pane >>>"
    private static let end = "# <<< soundcrest pane <<<"

    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func adding(to text: String, executable: String) -> String {
        let path = quoted(executable)
        return removing(from: text) + """

        \(begin)
        if [[ -o interactive && -t 0 && -t 1 && "$TERM_PROGRAM" == Apple_Terminal \\
              && -z "$TMUX" && -z "$SOUNDCREST_NO_PANE" && -x \(path) ]]; then
          exec \(path) --pane-shell
        fi
        \(end)

        """
    }

    public static func removing(from text: String) -> String {
        guard let start = text.range(of: "\n" + begin),
              let finish = text.range(of: end + "\n", range: start.upperBound..<text.endIndex)
        else { return text }
        return String(text[..<start.lowerBound] + text[finish.upperBound...])
    }

    /// Honours ZDOTDIR and follows a symlinked dotfile.
    public static var file: URL {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["ZDOTDIR"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".zshrc").resolvingSymlinksInPath()
    }

    public static func install(executable: String, in url: URL = file) throws {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try write(adding(to: text, executable: executable), to: url)
    }

    public static func remove(in url: URL = file) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let updated = removing(from: text)
        if updated != text { try write(updated, to: url) }
    }

    private static func write(_ text: String, to url: URL) throws {
        let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions as Any], ofItemAtPath: url.path)
        }
    }
}
