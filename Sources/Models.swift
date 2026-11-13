// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import Foundation

enum Mode: String, Codable, CaseIterable, Identifiable {
    case code, study, game, stopServer, clear
    var id: String { rawValue }
    var isQuitMode: Bool { self == .stopServer || self == .clear }
    var title: String {
        switch self {
        case .code: return "Code Mode"
        case .study: return "Study Mode"
        case .game: return "Game Mode"
        case .stopServer: return "Stop Server"
        case .clear: return "Clear Mode"
        }
    }
    var symbol: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .study: return "book.closed"
        case .game: return "gamecontroller"
        case .stopServer: return "server.rack"
        case .clear: return "sparkles"
        }
    }
    var subtitle: String {
        switch self {
        case .code: return "พร้อมเขียนโค้ด"
        case .study: return "จัดพื้นที่ให้พร้อมเรียน"
        case .game: return "ได้เวลาเล่นเกม"
        case .stopServer: return "ปิด Docker และ Terminal"
        case .clear: return "ปิดทุกแอป แล้วเริ่มใหม่"
        }
    }
}

struct AppTarget: Codable, Equatable, Identifiable {
    var name: String
    var bundleIdentifier: String?
    var path: String
    var id: String { bundleIdentifier ?? path }

    static let discord = AppTarget(name: "Discord", bundleIdentifier: "com.hnc.Discord", path: "/Applications/Discord.app")
    static let vscode = AppTarget(name: "VS Code", bundleIdentifier: "com.microsoft.VSCode", path: "/Applications/Visual Studio Code.app")
    static let terminal = AppTarget(name: "Terminal", bundleIdentifier: "com.apple.Terminal", path: "/System/Applications/Utilities/Terminal.app")
    static let firefox = AppTarget(name: "Firefox", bundleIdentifier: "org.mozilla.firefox", path: "/Applications/Firefox.app")
    static let docker = AppTarget(name: "Docker", bundleIdentifier: "com.docker.docker", path: "/Applications/Docker.app")

    init(name: String, bundleIdentifier: String?, path: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }

    init(url: URL) {
        let bundle = Bundle(url: url)
        name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        bundleIdentifier = bundle?.bundleIdentifier
        path = url.path
    }

    var resolvedURL: URL? {
        let preferred = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) { return preferred }
        if let bundleIdentifier {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        return nil
    }
}

struct Configuration: Codable, Equatable {
    var code: [AppTarget] = [.discord, .vscode, .terminal]
    var study: [AppTarget] = [.discord, .firefox, .vscode, .terminal]
    var game: [AppTarget] = [.discord]
    var includeMenuBarApps = true

    subscript(mode: Mode) -> [AppTarget] {
        get {
            switch mode {
            case .code: return code
            case .study: return study
            case .game: return game
            case .stopServer: return [.docker, .terminal]
            case .clear: return []
            }
        }
        set {
            switch mode {
            case .code: code = newValue
            case .study: study = newValue
            case .game: game = newValue
            case .stopServer, .clear: break
            }
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var configuration: Configuration {
        didSet { save() }
    }
    @Published var persistenceError: String?
    private let defaults: UserDefaults?
    private static let key = "ModeBar.configuration.v1"

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key), let value = try? JSONDecoder().decode(Configuration.self, from: data) {
            configuration = value
        } else {
            configuration = Configuration()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(configuration)
            defaults?.set(data, forKey: Self.key)
            persistenceError = nil
        } catch {
            persistenceError = "บันทึกการตั้งค่าไม่ได้: \(error.localizedDescription)"
        }
    }

    func add(_ target: AppTarget, to mode: Mode) {
        guard !configuration[mode].contains(where: { $0.id == target.id }) else { return }
        configuration[mode].append(target)
    }

    func move(_ target: AppTarget, in mode: Mode, offset: Int) {
        var apps = configuration[mode]
        guard let index = apps.firstIndex(of: target), apps.indices.contains(index + offset) else { return }
        apps.swapAt(index, index + offset)
        configuration[mode] = apps
    }

    func remove(_ target: AppTarget, from mode: Mode) {
        configuration[mode].removeAll { $0.id == target.id }
    }
}

struct AppProcess: Equatable, Identifiable {
    var pid: Int32
    var name: String
    var bundleIdentifier: String?
    var path: String?
    var policy: Int
    var id: Int32 { pid }

    init(pid: Int32, name: String, bundleIdentifier: String?, path: String?, policy: Int) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.policy = policy
    }

    init(_ app: NSRunningApplication) {
        self.init(pid: app.processIdentifier, name: app.localizedName ?? "Application",
                  bundleIdentifier: app.bundleIdentifier, path: app.bundleURL?.path,
                  policy: app.activationPolicy.rawValue)
    }
}

enum QuitPolicy {
    static func includes(_ app: AppProcess, currentPID: Int32, menuBarApps: Bool) -> Bool {
        guard app.pid > 0, app.pid != currentPID,
              app.bundleIdentifier != "com.apple.finder",
              app.bundleIdentifier != "org.modebar.ModeBar" else { return false }
        if app.policy == NSApplication.ActivationPolicy.regular.rawValue { return true }
        guard menuBarApps, app.policy == NSApplication.ActivationPolicy.accessory.rawValue,
              let path = app.path, !path.hasPrefix("/System/"), !path.hasPrefix("/usr/") else { return false }
        // A launchable menu bar app is eligible; nested helpers and system agents are not.
        guard path.hasSuffix(".app"), !path.contains(".app/"), !path.contains("/Library/") else { return false }
        return true
    }
}
