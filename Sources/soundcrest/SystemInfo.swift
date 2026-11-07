#if os(macOS)
import Darwin
import Foundation
import IOKit
import IOKit.ps
import WaveCore

/// Reads what the pane's info panel shows. Fixed facts are read once;
/// `fields()` re-reads the ones that change.
struct SystemInfo {
    let header: String
    private let os: String
    private let host: String
    private let kernel: String
    private let shell: String
    private let cpu: String

    init() {
        let processInfo = ProcessInfo.processInfo
        let user = processInfo.environment["USER"] ?? NSUserName()
        let hostName = (Self.sysctlString("kern.hostname") ?? processInfo.hostName)
            .split(separator: ".").first.map(String.init) ?? "mac"
        header = "\(user)@\(hostName)"

        let version = processInfo.operatingSystemVersion
        let number = version.patchVersion > 0
            ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            : "\(version.majorVersion).\(version.minorVersion)"
        let name = Self.releaseNames[version.majorVersion].map { " \($0)" } ?? ""
        os = "macOS\(name) \(number)"

        host = Self.productName() ?? Self.sysctlString("hw.model") ?? "Mac"
        kernel = "Darwin " + (Self.sysctlString("kern.osrelease") ?? "?")
        shell = (processInfo.environment["SHELL"] ?? "/bin/zsh").split(separator: "/").last.map(String.init) ?? "zsh"

        let brand = Self.sysctlString("machdep.cpu.brand_string") ?? "?"
        let cores = Self.sysctlInt("hw.ncpu").map { " (\($0))" } ?? ""
        cpu = brand + cores
    }

    func fields() -> [InfoPanel.Field] {
        var fields = [
            InfoPanel.Field("OS", os),
            InfoPanel.Field("Host", host),
            InfoPanel.Field("Kernel", kernel),
        ]
        if let uptime = Self.uptimeSeconds() { fields.append(.init("Uptime", InfoPanel.uptime(seconds: uptime))) }
        if let packages = Self.brewPackages() { fields.append(.init("Packages", "\(packages) (brew)")) }
        fields.append(.init("Shell", shell))
        fields.append(.init("CPU", cpu))
        if let memory = Self.memory() { fields.append(.init("Memory", InfoPanel.usage(used: memory.used, total: memory.total))) }
        if let disk = Self.disk() { fields.append(.init("Disk", InfoPanel.usage(used: disk.used, total: disk.total))) }
        if let battery = Self.battery() { fields.append(.init("Battery", battery)) }
        return fields
    }

    private static let releaseNames = [
        11: "Big Sur", 12: "Monterey", 13: "Ventura", 14: "Sonoma", 15: "Sequoia", 26: "Tahoe",
    ]

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    /// Marketing name such as "MacBook Pro (14-inch, Nov 2023)" on Apple silicon.
    private static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    private static func uptimeSeconds() -> Int? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return max(Int(Date().timeIntervalSince1970) - boot.tv_sec, 0)
    }

    private static func brewPackages() -> Int? {
        let manager = FileManager.default
        let counts = ["/opt/homebrew/Cellar", "/opt/homebrew/Caskroom", "/usr/local/Cellar", "/usr/local/Caskroom"]
            .compactMap { try? manager.contentsOfDirectory(atPath: $0).filter { !$0.hasPrefix(".") }.count }
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    /// Wired + active + compressed, as Activity Monitor and neofetch count it.
    private static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.wire_count) + UInt64(stats.active_count) + UInt64(stats.compressor_page_count)
        return (pages * UInt64(vm_kernel_page_size), ProcessInfo.processInfo.physicalMemory)
    }

    private static func disk() -> (used: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let totalBytes = UInt64(total)
        return (totalBytes - min(UInt64(max(free, 0)), totalBytes), totalBytes)
    }

    /// `84% charging`, or nil on Macs without a battery.
    private static func battery() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let percent = current * 100 / max
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return "\(percent)%" + (charging ? " charging" : plugged ? " plugged in" : "")
        }
        return nil
    }
}
#endif
