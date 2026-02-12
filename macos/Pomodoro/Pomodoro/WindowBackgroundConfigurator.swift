//
//  WindowBackgroundConfigurator.swift
//  Pomodoro
//
//  Configures the NSWindow to support wallpaper blur while keeping a hidden titlebar with visible controls.
//

import AppKit
import SwiftUI

/// Configures the NSWindow to support wallpaper blur and hidden chrome.
///
/// Responsibilities:
/// - Enables true wallpaper blur by making the window non-opaque with a clear background
/// - Hides the title text and titlebar separator while keeping the traffic lights visible
/// - Keeps the header invisible so the content can bleed into the titlebar
/// - Preserves window dragging by allowing the full background to act as a drag region
struct WindowBackgroundConfigurator: NSViewRepresentable {
    final class HostingView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWindowStyling()
        }

        func applyWindowStyling() {
            guard let window else { return }
            window.identifier = .pomodoroMainWindow
            window.applyPomodoroWindowChrome()
        }
    }

    func makeNSView(context: Context) -> HostingView {
        HostingView()
    }

    func updateNSView(_ nsView: HostingView, context: Context) {}
}

extension NSWindow {
    /// Applies the app's chrome preferences:
    /// - Transparent title bar with hidden title text
    /// - Visible traffic light controls
    /// - Preserves drag gestures on the window background
    /// - Keeps the header visually invisible
    func applyPomodoroWindowChrome() {
        guard level == .normal else { return }

        // Enable transparent window compositing so the content can fill the titlebar area.
        isOpaque = false
        backgroundColor = .clear

        // Keep native controls while hiding title text and making the titlebar transparent.
        title = ""
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        styleMask.insert(.titled)
        styleMask.insert(.fullSizeContentView)
        styleMask.insert(.closable)
        styleMask.insert(.miniaturizable)
        styleMask.insert(.resizable)
        toolbarStyle = .unified
        isMovableByWindowBackground = true
    }
}

extension NSUserInterfaceItemIdentifier {
    static let pomodoroMainWindow = NSUserInterfaceItemIdentifier("PomodoroMainWindow")
}
