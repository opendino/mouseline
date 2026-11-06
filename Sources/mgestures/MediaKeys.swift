import AppKit
import os

private let log = Logger(subsystem: "dev.mgestures.app", category: "media")

/// Simulates the media keys of an Apple keyboard (F7–F12 row).
///
/// These keys are not ordinary key codes: the keyboard driver reports them as
/// `NSEvent.EventType.systemDefined` events with subtype 8 (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`),
/// carrying the `NX_KEYTYPE_*` code and the key state in `data1`. Posting such an event at the
/// HID tap makes the system behave exactly as if the key had been pressed: the volume HUD
/// appears, and play/pause/next go to whichever app currently owns "Now Playing".
@MainActor
enum MediaKeys {
    /// `NX_KEYTYPE_*` values from IOKit's `ev_keymap.h`.
    enum Key: Int {
        case soundUp = 0
        case soundDown = 1
        case mute = 7
        case play = 16
        case next = 17
        case previous = 18
    }

    /// Posts a key-down followed by a key-up for `key`.
    static func press(_ key: Key) {
        post(key, down: true)
        post(key, down: false)
    }

    private static func post(_ key: Key, down: Bool) {
        // modifierFlags 0xa00 / 0xb00 and data1's state byte 0xa / 0xb mirror what the real
        // keyboard driver sends for key down / key up (NX_KEYDOWN = 10, NX_KEYUP = 11).
        let state = down ? 0xa : 0xb
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key.rawValue << 16) | (state << 8),
            data2: -1
        )
        guard let cgEvent = event?.cgEvent else {
            log.error("Could not create media key event \(key.rawValue)")
            return
        }
        cgEvent.post(tap: .cghidEventTap)
    }
}
