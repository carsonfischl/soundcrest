import os

/// Mono ring buffer between the Core Audio IO thread and the render loop.
/// The writer only try-locks, so the realtime thread never blocks; on the rare
/// contended callback it drops that block, which is harmless for a visualizer.
public final class SampleRing: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let capacity: Int
    private var head = 0
    private var written = 0

    public init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deallocate()
        lock.deallocate()
    }

    /// Realtime safe. Averages `channels` interleaved channels down to mono.
    public func write(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) {
        guard channels > 0, os_unfair_lock_trylock(lock) else { return }
        defer { os_unfair_lock_unlock(lock) }
        let scale = 1 / Float(channels)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += samples[frame * channels + channel] }
            storage[head] = sum * scale
            head = (head + 1) % capacity
        }
        written += frames
    }

    /// Zeroes the buffer so samples from before a pause are not redrawn.
    public func clear() {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        storage.update(repeating: 0, count: capacity)
    }

    /// Frames received so far; tells "no callbacks" apart from "only silence".
    public var framesWritten: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return written
    }

    /// Copies the newest `out.count` samples, oldest first.
    public func readLatest(into out: inout [Float]) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        var index = (head + capacity - (out.count % capacity)) % capacity
        for i in out.indices {
            out[i] = storage[index]
            index = (index + 1) % capacity
        }
    }
}
