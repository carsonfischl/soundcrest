/// A shell on the left and the waveform in a right column, on tmux with its own
/// server, so it looks like a plain terminal and ignores any personal tmux setup.
public enum PaneLayout {
    public static let width = 24
    public static let height = 6
    private static let minimumCols = 80
    private static let socket = "soundcrest"

    public static func fits(cols: Int) -> Bool { cols >= minimumCols }

    public static func tmuxArguments(tmux: String, shell: String, executable: String) -> [String] {
        let kill = "\(ShellHook.quoted(tmux)) -L \(socket) kill-session"
        let commands: [[String]] = [
            ["start-server"],
            ["set-option", "-g", "status", "off"],
            ["set-option", "-g", "prefix", "None"],
            ["set-option", "-g", "prefix2", "None"],
            ["set-option", "-g", "mode-keys", "emacs"],
            ["set-option", "-g", "escape-time", "0"],
            ["set-option", "-g", "history-limit", "50000"],
            ["set-option", "-g", "mouse", "on"],
            ["set-option", "-g", "destroy-unattached", "on"],
            ["set-option", "-g", "default-terminal", "screen-256color"],
            ["set-option", "-g", "terminal-features", "xterm-256color:RGB"],
            ["set-option", "-g", "pane-border-style", "fg=colour238"],
            ["set-option", "-g", "pane-active-border-style", "fg=colour238"],
            ["set-hook", "-g", "client-resized", "resize-pane -t :.1 -x \(width)"],
            // Keep typing in the shell, and copy selections to the clipboard.
            ["bind-key", "-n", "MouseDown1Pane", "select-pane", "-t", ":.0"],
            ["unbind-key", "-n", "MouseDrag1Border"],
            ["bind-key", "-T", "copy-mode", "MouseDragEnd1Pane",
             "send-keys", "-X", "copy-pipe-and-cancel", "pbcopy"],
            ["new-session", "\(ShellHook.quoted(shell)) -l; \(kill)"],
            ["split-window", "-d", "-h", "-l", "\(width)", "\(ShellHook.quoted(executable)) --pane-run"],
        ]
        return ["-L", socket, "-f", "/dev/null"] + commands.flatMap { $0 + [";"] }.dropLast()
    }
}
