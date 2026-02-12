import AppKit
import Combine

final class MenuBarController {
    private static var liveStatusItem: NSStatusItem?

    private let appState: AppState
    private let statusItem: NSStatusItem
    private let openMainWindow: () -> Void
    private let quit: () -> Void
    private var stateObserver: AnyCancellable?

    init(appState: AppState, openMainWindow: @escaping () -> Void, quit: @escaping () -> Void) {
        self.appState = appState
        self.openMainWindow = openMainWindow
        self.quit = quit
        if let existingItem = Self.liveStatusItem {
            NSStatusBar.system.removeStatusItem(existingItem)
            Self.liveStatusItem = nil
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.liveStatusItem = statusItem
        observeAppState()
        configureStatusItem()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
        if let liveItem = Self.liveStatusItem, liveItem === statusItem {
            Self.liveStatusItem = nil
        }
    }

    private func observeAppState() {
        stateObserver = appState.$currentMode.sink { [weak self] _ in
            self?.handleStateChange()
        }
    }

    private func handleStateChange() {
        updateStatusItemTitle()
    }

    private func configureStatusItem() {
        updateStatusItemTitle()

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open Pomodoro",
            action: #selector(openMainWindowAction),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        let modeName = appState.currentMode.displayName
        button.title = appState.currentMode == .idle ? "Pomodoro" : "Pomodoro • \(modeName)"
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    @objc private func quitAction() {
        quit()
    }
}
