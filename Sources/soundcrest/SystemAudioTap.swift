import CoreAudio
import Foundation
import WaveCore

enum TapError: LocalizedError {
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let call, let status): return "\(call) failed (OSStatus \(status))"
        }
    }
}

private func check(_ status: OSStatus, _ call: String) throws {
    if status != noErr { throw TapError.coreAudio(call, status) }
}

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, initial: T) throws -> T {
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    var property = address(selector)
    try withUnsafeMutablePointer(to: &value) {
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0), "read property")
    }
    return value
}

private func deviceUID(_ device: AudioDeviceID) throws -> String {
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var property = address(kAudioDevicePropertyDeviceUID)
    try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid), "read device UID")
    guard let uid else { throw TapError.coreAudio("read device UID", -1) }
    return uid.takeRetainedValue() as String
}

func defaultOutputDevice() throws -> AudioDeviceID {
    try read(kAudioHardwarePropertyDefaultOutputDevice,
             of: AudioObjectID(kAudioObjectSystemObject), initial: AudioDeviceID(0))
}

private func objectIDs(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) throws -> [AudioObjectID] {
    var property = address(selector)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "read list size")
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &ids), "read list")
    return ids
}

/// Whether any process but this one is sending audio to an output. Device-level
/// "is running" cannot answer this, because our own tap keeps the device running.
/// Assumes yes when Core Audio cannot be asked, so the display keeps working.
func otherProcessIsPlaying() -> Bool {
    let ownID = ProcessInfo.processInfo.processIdentifier
    guard let processes = try? objectIDs(kAudioHardwarePropertyProcessObjectList,
                                         of: AudioObjectID(kAudioObjectSystemObject)) else { return true }
    return processes.contains { process in
        (try? read(kAudioProcessPropertyIsRunningOutput, of: process, initial: UInt32(0))) == 1
            && (try? read(kAudioProcessPropertyPID, of: process, initial: pid_t(0))) != ownID
    }
}

/// Captures the system mix with a Core Audio process tap. The tap sits beside
/// normal playback: it needs no virtual device and does not change what plays.
final class SystemAudioTap {
    private let ring: SampleRing
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private(set) var outputDevice = AudioDeviceID(0)
    private(set) var sampleRate: Float = 48_000
    var isRunning: Bool { procID != nil }

    init(ring: SampleRing) { self.ring = ring }

    deinit { stop() }

    func start() throws {
        do {
            try open()
        } catch {
            stop()  // Callers may retry, so a partial start must not leak.
            throw error
        }
    }

    private func open() throws {
        outputDevice = try defaultOutputDevice()
        let outputUID = try deviceUID(outputDevice)

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "soundcrest"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")

        let format = try read(kAudioTapPropertyFormat, of: tapID, initial: AudioStreamBasicDescription())
        sampleRate = Float(format.mSampleRate)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "soundcrest",
            kAudioAggregateDeviceUIDKey: "local.soundcrest.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                  "AudioHardwareCreateAggregateDevice")

        let ring = self.ring
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, _, _ in
            // Tap buffers are Float32. Non-interleaved streams arrive as one
            // buffer per channel; the first is enough to draw from.
            guard input.pointee.mNumberBuffers > 0 else { return }
            let buffer = input.pointee.mBuffers
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { return }
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            ring.write(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
