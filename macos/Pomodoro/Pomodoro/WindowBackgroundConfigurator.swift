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
            window.applyPomodoroWindowChrome()
        }
    }

    func makeNSView(context: Context) -> HostingView {
        HostingView()
    }

    func updateNSView(_ nsView: HostingView, context: Context) {
        nsView.applyWindowStyling()
    }
}

extension NSWindow {
    /// Applies the app's chrome preferences:
    /// - Transparent title bar with hidden title text
    /// - Visible traffic light controls
    /// - Preserves drag gestures on the window background
    /// - Keeps the header visually invisible
    func applyPomodoroWindowChrome() {
        // Enable wallpaper blur support
        isOpaque = false
        backgroundColor = .clear

        // Hide the textual title while keeping the chrome area
        title = ""
        titleVisibility = .hidden
        // Let AppKit draw its native titlebar material; keep it transparent so our blur can show through.
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        styleMask.formUnion([.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable])
        toolbarStyle = .unified
        isMovableByWindowBackground = true

        showTrafficLights()
    }

    private func showTrafficLights() {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        // Make sure the titlebar container stays visible even though the chrome is hidden
        if let titlebarView = standardWindowButton(.closeButton)?.superview {
            titlebarView.isHidden = false
            titlebarView.alphaValue = 1
            titlebarView.superview?.isHidden = false
            titlebarView.superview?.alphaValue = 1
        }

        buttons.forEach { type in
            guard let button = standardWindowButton(type) else { return }
            button.isHidden = false
            button.isEnabled = true
            button.superview?.isHidden = false
        }
    }
}
