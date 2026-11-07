#if canImport(os)
import os
#else
import Glibc
#endif

/// The lock `SampleRing` needs: `os_unfair_lock` on Apple platforms, a
/// pthread mutex elsewhere. Both support a non-blocking try for the audio thread.
final class RingLock: @unchecked Sendable {
    #if canImport(os)
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    #else
    private let lock: UnsafeMutablePointer<pthread_mutex_t>
    #endif

    init() {
        lock = .allocate(capacity: 1)
        #if canImport(os)
        lock.initialize(to: os_unfair_lock())
        #else
        lock.initialize(to: pthread_mutex_t())
        pthread_mutex_init(lock, nil)
        #endif
    }

    deinit {
        #if !canImport(os)
        pthread_mutex_destroy(lock)
        #endif
        lock.deallocate()
    }

    func tryLock() -> Bool {
        #if canImport(os)
        return os_unfair_lock_trylock(lock)
        #else
        return pthread_mutex_trylock(lock) == 0
        #endif
    }

    func acquire() {
        #if canImport(os)
        os_unfair_lock_lock(lock)
        #else
        pthread_mutex_lock(lock)
        #endif
    }

    func unlock() {
        #if canImport(os)
        os_unfair_lock_unlock(lock)
        #else
        pthread_mutex_unlock(lock)
        #endif
    }
}
