#if os(Linux)
import Foundation
import Glibc
import WaveCore

/// What the pane's info view shows on Linux, read from /proc, /sys and
/// /etc/os-release. Fixed facts are read once; `fields()` re-reads the rest.
struct SystemInfo {
    let header: String
    private let os: String
    private let host: String?
    private let kernel: String
    private let shell: String
    private let cpu: String

    init() {
        let environment = ProcessInfo.processInfo.environment
        let user = environment["USER"] ?? NSUserName()
        var name = [CChar](repeating: 0, count: 256)
        let hostName = gethostname(&name, name.count) == 0 ? String(cString: name) : "linux"
        header = "\(user)@\(hostName.split(separator: ".").first.map(String.init) ?? hostName)"

        let osRelease = Self.text("/etc/os-release") ?? ""
        os = LinuxSystem.osName(osRelease: osRelease) ?? "Linux"
        host = Self.model()
        var system = utsname()
        uname(&system)
        let release = withUnsafeBytes(of: &system.release) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        kernel = "Linux " + release
        shell = (environment["SHELL"] ?? "/bin/sh").split(separator: "/").last.map(String.init) ?? "sh"
        let model = Self.text("/proc/cpuinfo").flatMap { LinuxSystem.cpuModel(cpuinfo: $0) }
            ?? withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        cpu = "\(model) (\(ProcessInfo.processInfo.activeProcessorCount))"
    }

    func fields() -> [InfoPanel.Field] {
        var fields = [InfoPanel.Field("OS", os)]
        if let host { fields.append(.init("Host", host)) }
        fields.append(.init("Kernel", kernel))
        if let uptime = Self.text("/proc/uptime").flatMap({ LinuxSystem.uptime(procUptime: $0) }) {
            fields.append(.init("Uptime", InfoPanel.uptime(seconds: uptime)))
        }
        if let packages = Self.packages() { fields.append(.init("Packages", packages)) }
        fields.append(.init("Shell", shell))
        fields.append(.init("CPU", cpu))
        if let memory = Self.text("/proc/meminfo").flatMap({ LinuxSystem.memory(meminfo: $0) }) {
            fields.append(.init("Memory", InfoPanel.usage(used: memory.used, total: memory.total)))
        }
        if let disk = Self.disk() { fields.append(.init("Disk", InfoPanel.usage(used: disk.used, total: disk.total))) }
        if let battery = Self.battery() { fields.append(.init("Battery", battery)) }
        return fields
    }

    private static func text(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    /// Laptop or board name: DMI on PCs, the device tree on ARM boards.
    private static func model() -> String? {
        let clean = { (value: String?) -> String? in
            let text = value?.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let placeholders = ["", "To Be Filled By O.E.M.", "System Product Name", "Default string", "None"]
            return text.flatMap { placeholders.contains($0) ? nil : $0 }
        }
        if let product = clean(text("/sys/devices/virtual/dmi/id/product_name")) {
            let vendor = clean(text("/sys/devices/virtual/dmi/id/sys_vendor"))
            return vendor.map { product.hasPrefix($0) ? product : "\($0) \(product)" } ?? product
        }
        return clean(text("/proc/device-tree/model"))
    }

    /// `1843 (dpkg), 12 (flatpak)`, counting the managers that are present.
    private static func packages() -> String? {
        let manager = FileManager.default
        var counts: [String] = []
        if let status = text("/var/lib/dpkg/status") { counts.append("\(LinuxSystem.dpkgCount(status: status)) (dpkg)") }
        if let pacman = try? manager.contentsOfDirectory(atPath: "/var/lib/pacman/local") {
            counts.append("\(pacman.filter { $0 != "ALPM_DB_VERSION" }.count) (pacman)")
        }
        if let flatpak = try? manager.contentsOfDirectory(atPath: "/var/lib/flatpak/app"), !flatpak.isEmpty {
            counts.append("\(flatpak.count) (flatpak)")
        }
        if let brew = try? manager.contentsOfDirectory(atPath: "/home/linuxbrew/.linuxbrew/Cellar"), !brew.isEmpty {
            counts.append("\(brew.count) (brew)")
        }
        return counts.isEmpty ? nil : counts.joined(separator: ", ")
    }

    private static func disk() -> (used: UInt64, total: UInt64)? {
        var stats = statvfs()
        guard statvfs("/", &stats) == 0 else { return nil }
        let block = UInt64(stats.f_frsize)
        let total = UInt64(stats.f_blocks) * block
        let available = UInt64(stats.f_bavail) * block
        return total > 0 ? (total - min(available, total), total) : nil
    }

    private static func battery() -> String? {
        let root = "/sys/class/power_supply"
        let supplies = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        for supply in supplies.sorted() where text("\(root)/\(supply)/type")?.hasPrefix("Battery") == true {
            if let capacity = text("\(root)/\(supply)/capacity") {
                return LinuxSystem.battery(capacity: capacity, status: text("\(root)/\(supply)/status") ?? "")
            }
        }
        return nil
    }
}
#endif
