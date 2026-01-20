//
//  AppleScriptRunner.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import Foundation

enum AppleScriptRunner {
    static func run(_ script: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let appleScript = NSAppleScript(source: script)
                var error: NSDictionary?
                let result = appleScript?.executeAndReturnError(&error)
                continuation.resume(returning: result)
            }
        }
    }
}

extension NSAppleEventDescriptor {
    /// Safely reads a list descriptor by 1-based index.
    func descriptor(at index: Int) -> NSAppleEventDescriptor? {
        guard descriptorType == typeAEList else { return nil }
        return atIndex(index)
    }
}
