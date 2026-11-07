#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// The pane's event loop: sleeps between frames in `poll`, waking early for
/// key presses or for work other threads post, such as network replies. It
/// stands in for the main run loop, which Linux's Foundation doesn't drive.
enum MainLoop {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var work: [() -> Void] = []
    nonisolated(unsafe) private static var wakeFDs: [Int32] = {
        var fds: [Int32] = [-1, -1]
        if pipe(&fds) == 0 {
            for fd in fds { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        }
        return fds
    }()

    /// Runs `block` on the loop's thread at its next wake-up. Safe from any thread.
    static func post(_ block: @escaping () -> Void) {
        lock.lock()
        work.append(block)
        lock.unlock()
        var byte: UInt8 = 1
        _ = write(wakeFDs[1], &byte, 1)
    }

    enum Input {
        case bytes([UInt8])
        case closed
    }

    /// Waits up to `seconds`, runs any posted work, and returns what arrived
    /// on `input` (nil if nothing).
    static func wait(seconds: Double, input: Int32?) -> Input? {
        var fds = [pollfd(fd: wakeFDs[0], events: Int16(POLLIN), revents: 0)]
        if let input { fds.append(pollfd(fd: input, events: Int16(POLLIN), revents: 0)) }
        _ = poll(&fds, nfds_t(fds.count), Int32(max(seconds, 0) * 1000))

        if fds[0].revents != 0 {
            var drain = [UInt8](repeating: 0, count: 64)
            while read(wakeFDs[0], &drain, drain.count) > 0 {}
        }
        lock.lock()
        let pending = work
        work.removeAll()
        lock.unlock()
        pending.forEach { $0() }

        guard let input, fds.count > 1, fds[1].revents != 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(input, &buffer, buffer.count)
        if count > 0 { return .bytes(Array(buffer[..<count])) }
        return count == 0 || fds[1].revents & Int16(POLLHUP) != 0 ? .closed : nil
    }
}
