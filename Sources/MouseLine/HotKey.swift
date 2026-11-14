import Carbon.HIToolbox
import MouseLineCore
import os

private let log = Logger(subsystem: "app.mouseline", category: "hotkey")

/// A global keyboard shortcut, registered with the Carbon hot key API.
///
/// Carbon hot keys are delivered by the system only for the registered combination, so this
/// needs no Accessibility access and never observes the rest of the keyboard — unlike an
/// event tap or a global NSEvent monitor. The API is old but still the supported way to do
/// this on current macOS.
///
/// One instance holds at most one hot key; it is meant to live as long as the app (there is
/// no deinit cleanup, because the registration ends with the process anyway).
@MainActor
final class HotKeyCenter {
    /// "mgst": identifies our hot keys in the shared application event target.
    private static let signature: OSType = 0x6D67_7374

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Registers `combo` as the hot key, replacing any previous registration; nil unregisters.
    ///
    /// Combinations without ⌘, ⌃ or ⌥ are refused (see `isUsable`), because they would take
    /// a plain key or ⇧-key away from every other app.
    func register(_ combo: KeyCombo?, handler: @escaping () -> Void) {
        unregister()
        guard let combo else { return }
        guard Self.isUsable(combo) else {
            log.notice("Ignoring hot key \(combo.display, privacy: .public): needs ⌘, ⌃ or ⌥")
            return
        }
        guard installEventHandlerIfNeeded() else { return }

        hotKeyID &+= 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), Self.carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: Self.signature, id: hotKeyID),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            // Typically eventHotKeyExistsErr: another app already owns this combination.
            log.error("Could not register hot key \(combo.display, privacy: .public) (status \(status))")
            return
        }
        hotKeyRef = ref
        self.handler = handler
        log.info("Registered hot key \(combo.display, privacy: .public)")
    }

    /// A shortcut can be global only if it has at least one of ⌘ ⌃ ⌥.
    static func isUsable(_ combo: KeyCombo) -> Bool {
        combo.modifiers & (KeyCombo.commandMask | KeyCombo.controlMask | KeyCombo.optionMask) != 0
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        handler = nil
    }

    /// The handler is installed once and stays; it ignores events for ids it does not own.
    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyEventCallback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &ref
        )
        guard status == noErr else {
            log.error("Could not install hot key handler (status \(status))")
            return false
        }
        eventHandler = ref
        return true
    }

    fileprivate func handle(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard status == noErr, id.signature == Self.signature, id.id == hotKeyID, hotKeyRef != nil else {
            return OSStatus(eventNotHandledErr)
        }
        handler?()
        return noErr
    }

    /// CGEventFlags modifier bits (as stored in `KeyCombo`) → Carbon modifier flags.
    private static func carbonModifiers(_ flags: UInt64) -> UInt32 {
        var result = 0
        if flags & KeyCombo.commandMask != 0 { result |= cmdKey }
        if flags & KeyCombo.optionMask != 0 { result |= optionKey }
        if flags & KeyCombo.controlMask != 0 { result |= controlKey }
        if flags & KeyCombo.shiftMask != 0 { result |= shiftKey }
        return UInt32(result)
    }
}

/// C-compatible trampoline into `HotKeyCenter.handle`. Handlers installed on the application
/// event target are called on the main thread.
private func hotKeyEventCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated { center.handle(event) }
}
