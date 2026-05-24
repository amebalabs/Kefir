import SwiftUI
import SwiftKEF
import AsyncHTTPClient
import KeyboardShortcuts

@main
struct KefirMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState ?? AppState())
                .frame(width: CGFloat(Constants.UI.settingsWidth), height: CGFloat(Constants.UI.settingsHeight))
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var appState: AppState!
    var miniPlayerWindowController: MiniPlayerWindowController?

    /// Global mouse-down monitor that dismisses the popover on an outside
    /// click. `.transient` alone is unreliable here because we force-activate
    /// the app and make the popover key (so SwiftUI controls receive clicks on
    /// macOS 14+), which suppresses the system transient dismissal.
    private var outsideClickMonitor: Any?
    
    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await appState?.cleanup()
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock
        NSApp.setActivationPolicy(.accessory)
        
        // Create app state
        appState = AppState()
        
        // Set up mini player keyboard shortcut
        KeyboardShortcuts.onKeyUp(for: .toggleMiniPlayer) { [weak self] in
            Task { @MainActor in
                self?.toggleMiniPlayer()
            }
        }
        
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Constants.Symbols.speaker, accessibilityDescription: Constants.App.name)
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: PopoverView(appState: appState, appDelegate: self))
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        
        // Monitor window notifications to handle settings window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    @objc func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window.title == "Settings" || window.title.contains("Preferences") {
            // Return to accessory mode when settings window closes
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    @MainActor @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                // Activate the app *before* showing the popover so the popover
                // window can become key and receive mouse/keyboard events.
                // `NSApp.activate(ignoringOtherApps:)` was deprecated in macOS 14
                // and is unreliable for `.accessory` apps on newer macOS releases.
                if #available(macOS 14.0, *) {
                    NSApp.activate()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }

                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // Make sure the popover's window is actually key, otherwise
                // SwiftUI controls inside it won't dispatch click events.
                popover.contentViewController?.view.window?.makeKey()

                installOutsideClickMonitor()
            }
        }
    }

    /// Installs a global monitor that closes the popover when the user clicks
    /// in any other application or on the desktop.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
    
    func showMiniPlayer() {
        DispatchQueue.main.async { [weak self] in
            if self?.miniPlayerWindowController == nil {
                self?.miniPlayerWindowController = MiniPlayerWindowController(appState: self?.appState ?? AppState())
            }
            self?.miniPlayerWindowController?.window?.makeKeyAndOrderFront(nil)
            self?.miniPlayerWindowController?.window?.orderFrontRegardless()
        }
    }
    
    func hideMiniPlayer() {
        DispatchQueue.main.async { [weak self] in
            self?.miniPlayerWindowController?.window?.close()
            self?.miniPlayerWindowController = nil
        }
    }
    
    func toggleMiniPlayer() {
        if miniPlayerWindowController?.window?.isVisible ?? false {
            hideMiniPlayer()
        } else {
            showMiniPlayer()
        }
    }
}

// MARK: - Keyboard Shortcut Names

extension KeyboardShortcuts.Name {
    static let volumeUp = Self("volumeUp")
    static let volumeDown = Self("volumeDown")
    static let toggleMute = Self("toggleMute")
    static let playPause = Self("playPause")
    static let nextTrack = Self("nextTrack")
    static let previousTrack = Self("previousTrack")
    static let toggleMiniPlayer = Self("toggleMiniPlayer")
}