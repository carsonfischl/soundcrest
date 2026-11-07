import Foundation

/// Parsers for the Linux files the info view reads. Kept free of file access
/// so they can be tested anywhere.
public enum LinuxSystem {
    /// `PRETTY_NAME` from /etc/os-release, e.g. "Ubuntu 24.04.1 LTS".
    public static func osName(osRelease: String) -> String? {
        let fields = Dictionary(osRelease.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")))
        }, uniquingKeysWith: { first, _ in first })
        return fields["PRETTY_NAME"] ?? fields["NAME"]
    }

    /// Used and total bytes from /proc/meminfo, counting MemAvailable as free.
    public static func memory(meminfo: String) -> (used: UInt64, total: UInt64)? {
        var kib: [String: UInt64] = [:]
        for line in meminfo.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == ":" || $0 == " " })
            if parts.count >= 2, let value = UInt64(parts[1]) { kib[String(parts[0])] = value }
        }
        guard let total = kib["MemTotal"], let available = kib["MemAvailable"] ?? kib["MemFree"] else { return nil }
        return ((total - min(available, total)) * 1024, total * 1024)
    }

    /// The CPU's name from /proc/cpuinfo. ARM boards often only say "Hardware"
    /// or nothing at all.
    public static func cpuModel(cpuinfo: String) -> String? {
        for key in ["model name", "Model", "Hardware", "cpu model"] {
            for line in cpuinfo.split(separator: "\n") where line.hasPrefix(key) {
                let value = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
                if !value.isEmpty, line.split(separator: ":").first?.trimmingCharacters(in: .whitespaces) == key {
                    return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                }
            }
        }
        return nil
    }

    /// Whole seconds from /proc/uptime.
    public static func uptime(procUptime: String) -> Int? {
        procUptime.split(separator: " ").first.flatMap { Double($0) }.map { Int($0) }
    }

    /// Installed packages in dpkg's status file.
    public static func dpkgCount(status: String) -> Int {
        status.components(separatedBy: "\n\n").filter { $0.contains("Status: install ok installed") }.count
    }

    /// `84% charging` from a power_supply's capacity and status files.
    public static func battery(capacity: String, status: String) -> String? {
        guard let percent = Int(capacity.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        switch status.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Charging": return "\(percent)% charging"
        case "Full", "Not charging": return "\(percent)% plugged in"
        default: return "\(percent)%"
        }
    }
}
