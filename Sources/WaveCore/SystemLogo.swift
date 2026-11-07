import Foundation

/// Small ASCII logos for the info view, neofetch style.
public enum SystemLogo {
    private static let apple = [
        #"       .:'    "#,
        #"   __ :'__    "#,
        #" .'  `-'  ``. "#,
        #":          .' "#,
        #":         :   "#,
        #" :         `. "#,
        #"  `.__.-.__.' "#,
    ]

    private static let tux = [
        #"    .--.     "#,
        #"   |o_o |    "#,
        #"   |:_/ |    "#,
        #"  //   \ \   "#,
        #" (|     | )  "#,
        #"/'\_   _/`\  "#,
        #"\___)=(___/  "#,
    ]

    private static let ubuntu = [
        #"          _   "#,
        #"      ---(_)  "#,
        #"  _/  ---  \  "#,
        #" (_) |   |    "#,
        #"   \  --- _/  "#,
        #"      ---(_)  "#,
    ]

    private static let debian = [
        #"   _____    "#,
        #"  /  __ \   "#,
        #" |  /    |  "#,
        #" |  \___-   "#,
        #" -_         "#,
        #"   --_      "#,
    ]

    private static let fedora = [
        #"      _____   "#,
        #"     /   __)\ "#,
        #"     |  /  \ \"#,
        #"  ___|  |__/ /"#,
        #" / (_    _)_/ "#,
        #"/ /  |  |     "#,
        #"\ \__/  |     "#,
        #" \(_____/     "#,
    ]

    private static let arch = [
        #"      /\       "#,
        #"     /  \      "#,
        #"    /\   \     "#,
        #"   /      \    "#,
        #"  /   ,,   \   "#,
        #" /   |  |  -\  "#,
        #"/_-''    ''-_\ "#,
    ]

    public static var macOS: [String] { padded(apple) }

    /// The logo for an /etc/os-release, matching `ID` first and then
    /// `ID_LIKE`, so Mint gets Ubuntu's and Manjaro gets Arch's. Tux otherwise.
    public static func linux(osRelease: String) -> [String] {
        let fields = Dictionary(osRelease.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).lowercased())
        }, uniquingKeysWith: { first, _ in first })
        let ids = [fields["ID"] ?? ""] + (fields["ID_LIKE"] ?? "").split(separator: " ").map(String.init)
        let logos = ["ubuntu": ubuntu, "debian": debian, "fedora": fedora, "rhel": fedora, "arch": arch]
        return padded(ids.lazy.compactMap { logos[$0] }.first ?? tux)
    }

    /// Every row the same width, so the details beside it line up.
    static func padded(_ rows: [String]) -> [String] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0.padding(toLength: width, withPad: " ", startingAt: 0) }
    }
}
