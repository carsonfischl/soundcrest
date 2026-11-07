import Foundation

/// The shell startup block that opens new terminal windows with the pane. It
/// has to stay safe at every shell start, so anything unexpected means a plain
/// shell.
public enum ShellHook {
    /// Which terminals get the pane.
    public enum Flavor: Sendable {
        /// Terminal.app on macOS, from `.zshrc`.
        case terminalApp
        /// Any local graphical terminal on Linux, from `.zshrc` or `.bashrc`.
        case linuxDesktop

        public static var current: Flavor {
            #if os(macOS)
            return .terminalApp
            #else
            return .linuxDesktop
            #endif
        }
    }

    private static let begin = "# >>> soundcrest pane >>>"
    private static let end = "# <<< soundcrest pane <<<"

    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func adding(to text: String, executable: String, flavor: Flavor = .current) -> String {
        let path = quoted(executable)
        let condition: String
        switch flavor {
        case .terminalApp:
            condition = """
            [[ -o interactive && -t 0 && -t 1 && "$TERM_PROGRAM" == Apple_Terminal \\
                  && -z "$TMUX" && -z "$SOUNDCREST_NO_PANE" && -x \(path) ]]
            """
        case .linuxDesktop:
            // Works in bash and zsh. Skips SSH sessions, editors' built-in
            // terminals and consoles without a display.
            condition = """
            [[ $- == *i* && -t 0 && -t 1 && -z "$TMUX" && -z "$SOUNDCREST_NO_PANE" \\
                  && -z "$SSH_CONNECTION" && -n "${DISPLAY:-$WAYLAND_DISPLAY}" \\
                  && "$TERM_PROGRAM" != vscode && -x \(path) ]]
            """
        }
        return removing(from: text) + """

        \(begin)
        if \(condition); then
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

    /// `.zshrc` (honouring ZDOTDIR) for zsh users and on macOS, otherwise
    /// `.bashrc`. Follows a symlinked dotfile.
    public static var file: URL {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let usesZsh = Flavor.current == .terminalApp || environment["SHELL"]?.hasSuffix("/zsh") == true
        guard usesZsh else { return home.appendingPathComponent(".bashrc").resolvingSymlinksInPath() }
        let directory = environment["ZDOTDIR"].map(URL.init(fileURLWithPath:)) ?? home
        return directory.appendingPathComponent(".zshrc").resolvingSymlinksInPath()
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
