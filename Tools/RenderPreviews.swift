// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import SwiftUI

// Render our own views to files for layout review; no screen capture or UI automation.
@main
enum RenderPreviews {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore(defaults: nil)
        let runner = ModeRunner(settings: settings, system: MacSystem())
        let menu = NSHostingView(rootView: MenuPanel(runner: runner, settings: settings, openSettings: {}, quit: {}))
        let preferences = NSHostingView(rootView: SettingsPanel(settings: settings))
        let menuWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 392, height: 620), styleMask: .borderless, backing: .buffered, defer: false)
        let preferencesWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 610), styleMask: .borderless, backing: .buffered, defer: false)
        menuWindow.contentView = menu
        preferencesWindow.contentView = preferences
        menuWindow.setContentSize(menu.fittingSize)
        menu.layoutSubtreeIfNeeded()
        preferences.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for (name, view) in [("ModeBar-menu", menu as NSView), ("ModeBar-settings", preferences as NSView)] {
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render \(name)") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                print("Rendered \(name): \(view.bounds.width) x \(view.bounds.height)")
            }
            withExtendedLifetime([menuWindow, preferencesWindow]) { exit(0) }
        }
        app.run()
    }
}
