/// A shell on the left and the waveform in a right column, on tmux with its own
/// server, so it looks like a plain terminal and ignores any personal tmux setup.
public enum PaneLayout {
    private static let socket = "soundcrest"

    /// Where copied text goes: pbcopy on macOS; on Linux wl-copy under Wayland,
    /// otherwise xclip.
    static var clipboardCommand: String {
        #if os(macOS)
        return "pbcopy"
        #else
        return "if [ -n \"$WAYLAND_DISPLAY\" ]; then wl-copy; else xclip -selection clipboard; fi"
        #endif
    }

    public static func tmuxArguments(tmux: String, shell: String, executable: String,
                                     paneCols: Int) -> [String] {
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
            ["set-hook", "-g", "client-resized", "resize-pane -t :.1 -x \(paneCols)"],
            // Keep typing in the shell, pass clicks to whichever pane wants them
            // (the waveform pane uses them to switch views and open articles),
            // and copy selections to the clipboard.
            ["bind-key", "-n", "MouseDown1Pane", "select-pane", "-t", ":.0", "\\;", "send-keys", "-M"],
            ["unbind-key", "-n", "MouseDrag1Border"],
            // Option-Tab (with Option as Meta) cycles the sections under the waveform.
            ["bind-key", "-n", "M-Tab", "send-keys", "-t", ":.1", "Tab"],
            ["bind-key", "-T", "copy-mode", "MouseDragEnd1Pane",
             "send-keys", "-X", "copy-pipe-and-cancel", clipboardCommand],
            ["new-session", "\(ShellHook.quoted(shell)) -l; \(kill)"],
            ["split-window", "-d", "-h", "-l", "\(paneCols)", "\(ShellHook.quoted(executable)) --pane-run"],
        ]
        return ["-L", socket, "-f", "/dev/null"] + commands.flatMap { $0 + [";"] }.dropLast()
    }
}
