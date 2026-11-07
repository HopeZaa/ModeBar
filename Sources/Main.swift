// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    lazy var runner = ModeRunner(settings: settings, system: MacSystem())
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ModeBarStatusItem"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("ModeBar เลือกโหมด")
        }
        let content = MenuPanel(runner: runner, settings: settings,
                                openSettings: { [weak self] in self?.showSettings() },
                                quit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: content)
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        runner.onStart = { [weak self] in self?.popover.performClose(nil) }
        runner.onStateChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        if ProcessInfo.processInfo.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showPopover() }
        }
    }

    private func createMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        let parent = NSMenuItem()
        parent.submenu = appMenu
        mainMenu.addItem(parent)
        let preferences = NSMenuItem(title: "ตั้งค่าโหมด…", action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(preferences)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "ออกจาก ModeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu
    }

    private func updateStatus() {
        let symbol = runner.isBusy ? "ellipsis.circle" : "square.stack.3d.up"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ModeBar")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "ModeBar · \(runner.status)"
        if popover.isShown, let view = popover.contentViewController?.view {
            DispatchQueue.main.async { [weak self] in
                self?.popover.contentSize = view.fittingSize
            }
        }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let preferences = NSMenuItem(title: "ตั้งค่าโหมด…", action: #selector(showSettings), keyEquivalent: ",")
            preferences.target = self
            preferences.isEnabled = !runner.isBusy
            menu.addItem(preferences)
            menu.addItem(.separator())
            menu.addItem(withTitle: "ออกจาก ModeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: sender)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        if let view = popover.contentViewController?.view { popover.contentSize = view.fittingSize }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func showSettings() {
        guard !runner.isBusy else { return }
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 610),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "ModeBar · ตั้งค่าโหมด"
            window.contentViewController = NSHostingController(rootView: SettingsPanel(settings: settings))
            window.minSize = NSSize(width: 710, height: 620)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }
}

@main
enum Main {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") {
            Task {
                let passed = await SelfTests.run()
                exit(passed ? 0 : 1)
            }
            RunLoop.main.run()
            return
        }
        if arguments.contains("--diagnostics") {
            let config = Configuration()
            let modes = [Mode.code, .study, .game].map { mode in
                ["mode": mode.rawValue, "apps": config[mode].map { ["name": $0.name, "path": $0.resolvedURL?.path ?? "MISSING"] }] as [String: Any]
            }
            let report: [String: Any] = ["version": "1.0", "modes": modes, "clearPreserves": ["Finder", "ModeBar"]]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        let app = NSApplication.shared
        if let index = arguments.firstIndex(of: "--verify-mode"), arguments.count > index + 1,
           let mode = Mode(rawValue: arguments[index + 1]), mode != .clear {
            app.setActivationPolicy(.accessory)
            Task {
                let runner = ModeRunner(settings: SettingsStore(defaults: nil), system: MacSystem())
                await runner.runForTesting(mode)
                let actual = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
                let expected = runner.settings.configuration[mode].last?.bundleIdentifier ?? "none"
                print("MODE=\(mode.rawValue) STATUS=\(runner.status) FRONTMOST=\(actual) EXPECTED=\(expected)")
                exit(!runner.hasError && actual == expected ? 0 : 1)
            }
            app.run()
            return
        }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "org.modebar.ModeBar")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            _ = existing.activate(options: [])
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
