#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Raw mode plus alternate screen, restored on exit.
final class Terminal {
    private var original = termios()
    private let isInteractive = isatty(STDIN_FILENO) == 1

    init() {
        if isInteractive {
            tcgetattr(STDIN_FILENO, &original)
            var raw = original
            raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J")
    }

    func restore() {
        write("\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        if isInteractive { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
    }

    func size() -> (cols: Int, rows: Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, windowSizeRequest, &size) == 0, size.ws_col > 0, size.ws_row > 0 else {
            return (80, 24)
        }
        return (Int(size.ws_col), Int(size.ws_row))
    }

    /// Returns a pending key press without blocking.
    func readKey() -> UInt8? {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 0) > 0 else { return nil }
        var key: UInt8 = 0
        return systemRead(STDIN_FILENO, &key, 1) == 1 ? key : nil
    }

    func write(_ text: String) { write(Array(text.utf8)) }

    func write(_ bytes: [UInt8]) {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { systemWrite(STDOUT_FILENO, $0.baseAddress, $0.count) }
            if written <= 0 { return }
            offset += written
        }
    }
}

#if canImport(Darwin)
private let systemRead = Darwin.read
private let systemWrite = Darwin.write
let windowSizeRequest = TIOCGWINSZ
#else
private let systemRead = Glibc.read
private let systemWrite = Glibc.write
let windowSizeRequest = UInt(TIOCGWINSZ)
#endif
