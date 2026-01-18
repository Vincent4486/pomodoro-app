import AppKit
import Combine

final class MenuBarController {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let openMainWindow: () -> Void
    private let quit: () -> Void
    private var stateObserver: AnyCancellable?

    init(appState: AppState, openMainWindow: @escaping () -> Void, quit: @escaping () -> Void) {
        self.appState = appState
        self.openMainWindow = openMainWindow
        self.quit = quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        observeAppState()
        configureStatusItem()
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
