#if os(macOS)
import AppKit
import Carbon

/// System-wide shortcut that turns the background off. Carbon hot keys work
/// from any app and do not need the Accessibility permission.
enum HotKey {
    static let title = "⌃⌥⌘W"

    static func install() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return noErr
        }, 1, &event, nil, nil)

        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: 0x534E_4443, id: 1),  // "SNDC"
                                         GetEventDispatcherTarget(), 0, &hotKey)
        if status != noErr { NSLog("soundcrest: could not register %@ (%d)", title, status) }
    }
}
#endif
