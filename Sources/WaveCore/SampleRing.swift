/// Mono ring buffer between the audio capture thread and the render loop.
/// The writer only try-locks, so the realtime thread never blocks; on the rare
/// contended callback it drops that block, which is harmless for a visualizer.
public final class SampleRing: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let lock = RingLock()
    private let capacity: Int
    private var head = 0
    private var written = 0

    public init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Realtime safe. Averages `channels` interleaved channels down to mono.
    public func write(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) {
        guard channels > 0, lock.tryLock() else { return }
        defer { lock.unlock() }
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
        lock.acquire()
        defer { lock.unlock() }
        storage.update(repeating: 0, count: capacity)
    }

    /// Frames received so far; tells "no callbacks" apart from "only silence".
    public var framesWritten: Int {
        lock.acquire()
        defer { lock.unlock() }
        return written
    }

    /// Copies the newest `out.count` samples, oldest first.
    public func readLatest(into out: inout [Float]) {
        lock.acquire()
        defer { lock.unlock() }
        var index = (head + capacity - (out.count % capacity)) % capacity
        for i in out.indices {
            out[i] = storage[index]
            index = (index + 1) % capacity
        }
    }
}
