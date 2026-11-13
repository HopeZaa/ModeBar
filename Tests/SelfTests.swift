// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import Foundation

@MainActor
private final class FakeSystem: ModeSystem {
    var currentPID: Int32 = 100
    var unavailable = Set<String>()
    var failingID: String?
    var launches: [String] = []
    var webpages: [URL?] = []
    var activations: [AppProcess] = []
    var terminated: [AppProcess] = []
    var processes: [AppProcess] = []
    var blockedPIDs = Set<Int32>()
    var activationSucceeds = true
    var quitAfterWaitCount: Int?
    var waitCount = 0
    func isAvailable(_ target: AppTarget) -> Bool { !unavailable.contains(target.id) }
    func launch(_ target: AppTarget, opening webpage: URL?) async throws -> AppProcess {
        launches.append(target.id)
        webpages.append(webpage)
        if target.id == failingID { throw ModeError.launch(target.name) }
        return AppProcess(pid: Int32(200 + launches.count), name: target.name, bundleIdentifier: target.bundleIdentifier, path: target.path, policy: 0)
    }
    func activate(_ app: AppProcess) -> Bool { activations.append(app); return activationSucceeds }
    func runningApps() -> [AppProcess] { processes }
    func terminate(_ app: AppProcess) -> Bool {
        terminated.append(app)
        if !blockedPIDs.contains(app.pid) { processes.removeAll { $0.pid == app.pid } }
        return !blockedPIDs.contains(app.pid)
    }
    func wait(milliseconds: UInt64) async {
        waitCount += 1
        if waitCount == quitAfterWaitCount { processes.removeAll { blockedPIDs.contains($0.pid) } }
        await Task.yield()
    }
}

@MainActor
enum SelfTests {
    static func run() async -> Bool {
        var failures: [String] = []
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1
            if !condition() { failures.append(message); print("FAIL: \(message)") }
        }
        let defaults = Configuration()
        check(defaults.code.map(\.id) == [AppTarget.discord.id, AppTarget.vscode.id, AppTarget.terminal.id], "Code order")
        check(defaults.study.map(\.id) == [AppTarget.discord.id, AppTarget.firefox.id, AppTarget.vscode.id, AppTarget.terminal.id], "Study order / Terminal front")
        check(defaults.game == [.discord], "Game opens Discord only")
        check(defaults[.stopServer] == [.docker, .terminal], "Stop Server targets Docker and Terminal only")
        check(Mode.stopServer.isQuitMode && Mode.clear.isQuitMode && !Mode.code.isQuitMode, "Quit modes are identified separately from launch modes")
        let data = try! JSONEncoder().encode(defaults)
        check((try! JSONDecoder().decode(Configuration.self, from: data)) == defaults, "Configuration round trip")
        let store = SettingsStore(defaults: nil)
        store.add(.discord, to: .code)
        check(store.configuration.code.count == 3, "Duplicate prevented")
        store.move(.discord, in: .code, offset: -1)
        check(store.configuration.code.first == .discord, "Reorder boundary")
        store.move(.discord, in: .code, offset: 1)
        check(store.configuration.code[1] == .discord, "Reorder saves new launch order")
        store.remove(.discord, from: .code)
        check(store.configuration.code == [.vscode, .terminal], "Removal")

        for mode in [Mode.code, .study, .game] {
            let system = FakeSystem()
            let runner = ModeRunner(settings: SettingsStore(defaults: nil), system: system)
            await runner.runForTesting(mode)
            check(system.launches == defaults[mode].map(\.id), "\(mode) sequential launches")
            check(system.activations.last?.bundleIdentifier == defaults[mode].last?.bundleIdentifier, "\(mode) foreground")
            check(!runner.isBusy && !runner.hasError && runner.activeMode == mode, "\(mode) completion state")
            check(system.terminated.isEmpty, "\(mode) preserves other apps")
            let expectedURLs: [URL?] = defaults[mode].map {
                mode == .study && $0 == .firefox ? URL(string: "https://www.mycourseville.com/") : nil
            }
            check(system.webpages == expectedURLs, "\(mode) opens MyCourseVille only with Study Firefox")
        }
        let customStore = SettingsStore(defaults: nil)
        customStore.configuration.code = [.firefox]
        let customSystem = FakeSystem()
        let customRunner = ModeRunner(settings: customStore, system: customSystem)
        await customRunner.runForTesting(.code)
        check(customSystem.webpages == [nil], "Firefox in another mode does not open Study URL")
        let missingSystem = FakeSystem()
        missingSystem.unavailable.insert(AppTarget.vscode.id)
        let missingRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: missingSystem)
        await missingRunner.runForTesting(.code)
        check(missingSystem.launches.isEmpty && missingRunner.hasError && !missingRunner.isBusy, "Missing app preflight before any launch")

        let failing = FakeSystem()
        failing.failingID = AppTarget.vscode.id
        let failingRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: failing)
        await failingRunner.runForTesting(.code)
        check(failing.launches == [AppTarget.discord.id, AppTarget.vscode.id], "Failed launch stops sequence")
        check(failingRunner.hasError && !failingRunner.isBusy && failingRunner.activeMode == nil, "Failed launch state")

        let emptyStore = SettingsStore(defaults: nil)
        emptyStore.configuration.game = []
        let emptySystem = FakeSystem()
        let emptyRunner = ModeRunner(settings: emptyStore, system: emptySystem)
        await emptyRunner.runForTesting(.game)
        check(emptySystem.launches.isEmpty && emptyRunner.hasError, "Empty mode feedback")

        let noActivation = FakeSystem()
        noActivation.activationSucceeds = false
        let noActivationRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: noActivation)
        await noActivationRunner.runForTesting(.game)
        check(noActivationRunner.hasError && noActivationRunner.activeMode == nil, "Activation failure reported")

        let apps = [
            AppProcess(pid: 100, name: "ModeBar", bundleIdentifier: "org.modebar.ModeBar", path: "/Applications/ModeBar.app", policy: 1),
            AppProcess(pid: 101, name: "Finder", bundleIdentifier: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app", policy: 0),
            AppProcess(pid: 102, name: "Editor", bundleIdentifier: "test.editor", path: "/Applications/Editor.app", policy: 0),
            AppProcess(pid: 103, name: "MenuApp", bundleIdentifier: "test.menu", path: "/Applications/MenuApp.app", policy: 1),
            AppProcess(pid: 104, name: "Helper", bundleIdentifier: "test.helper", path: "/Applications/Editor.app/Contents/Frameworks/Helper.app", policy: 1),
            AppProcess(pid: 105, name: "Control Center", bundleIdentifier: "com.apple.controlcenter", path: "/System/Library/CoreServices/ControlCenter.app", policy: 1),
            AppProcess(pid: 106, name: "Agent", bundleIdentifier: "test.agent", path: "/Applications/Agent.app", policy: 2)
        ]
        check(apps.filter { QuitPolicy.includes($0, currentPID: 100, menuBarApps: true) }.map(\.pid) == [102, 103], "Clear eligibility preserves Finder/self/system/helpers")
        check(apps.filter { QuitPolicy.includes($0, currentPID: 100, menuBarApps: false) }.map(\.pid) == [102], "Clear menu app preference")
        let clearSystem = FakeSystem()
        clearSystem.processes = apps
        let clearRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: clearSystem)
        await clearRunner.runForTesting(.clear)
        check(clearSystem.terminated.map(\.pid) == [102, 103], "Clear terminates eligible apps")
        check(clearRunner.activeMode == .clear && !clearRunner.hasError && clearRunner.remainingApps.isEmpty, "Clear confirms actual termination")

        let blocked = FakeSystem()
        blocked.processes = apps
        blocked.blockedPIDs = [102]
        let blockedRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: blocked)
        await blockedRunner.runForTesting(.clear)
        check(blockedRunner.remainingApps.map(\.pid) == [102] && blockedRunner.hasError && blockedRunner.activeMode == nil, "Unsaved/refusing app reported")
        check(blocked.terminated.count == 2, "No repeated or forced quit")

        let lateQuit = FakeSystem()
        lateQuit.processes = apps
        lateQuit.blockedPIDs = [102]
        lateQuit.quitAfterWaitCount = 60
        let lateRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: lateQuit)
        await lateRunner.runForTesting(.clear)
        check(lateRunner.remainingApps.isEmpty && !lateRunner.hasError, "Termination in final wait is observed")

        let serverApps = [
            AppProcess(pid: 200, name: "Docker Desktop", bundleIdentifier: AppTarget.docker.bundleIdentifier, path: AppTarget.docker.path, policy: 1),
            AppProcess(pid: 201, name: "Terminal", bundleIdentifier: AppTarget.terminal.bundleIdentifier, path: AppTarget.terminal.path, policy: 0),
            AppProcess(pid: 202, name: "Discord", bundleIdentifier: AppTarget.discord.bundleIdentifier, path: AppTarget.discord.path, policy: 0),
            AppProcess(pid: 203, name: "VS Code", bundleIdentifier: AppTarget.vscode.bundleIdentifier, path: AppTarget.vscode.path, policy: 0),
            AppProcess(pid: 204, name: "Docker Helper", bundleIdentifier: "com.docker.backend", path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend", policy: 2),
            AppProcess(pid: 205, name: "Terminal", bundleIdentifier: "test.other-terminal", path: "/Applications/OtherTerminal.app", policy: 0),
            AppProcess(pid: 206, name: "Docker", bundleIdentifier: nil, path: "/Applications/OtherDocker.app", policy: 0),
            apps[0], apps[1]
        ]
        let serverSystem = FakeSystem()
        serverSystem.processes = serverApps
        let serverSettings = SettingsStore(defaults: nil)
        serverSettings.configuration.includeMenuBarApps = false
        let serverRunner = ModeRunner(settings: serverSettings, system: serverSystem)
        await serverRunner.runForTesting(.stopServer)
        check(serverSystem.terminated.map(\.pid) == [200, 201], "Stop Server quits Docker menu app and Terminal regardless of Clear preference")
        check(serverSystem.launches.isEmpty && serverSystem.activations.isEmpty, "Stop Server never launches or raises target apps")
        check(Set(serverSystem.processes.map(\.pid)) == [100, 101, 202, 203, 204, 205, 206], "Stop Server preserves other apps, helpers, and similarly named apps")
        check(serverRunner.activeMode == .stopServer && !serverRunner.isBusy && !serverRunner.hasError, "Stop Server completion state")

        let stoppedSystem = FakeSystem()
        stoppedSystem.processes = apps
        let stoppedRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: stoppedSystem)
        await stoppedRunner.runForTesting(.stopServer)
        check(stoppedSystem.terminated.isEmpty && stoppedSystem.launches.isEmpty, "Already stopped apps do not need to be installed or launched")
        check(stoppedRunner.activeMode == .stopServer && !stoppedRunner.hasError && stoppedRunner.detail == "Docker และ Terminal ปิดอยู่แล้ว", "Already stopped mode reports success")

        let waitingServer = FakeSystem()
        waitingServer.processes = serverApps
        waitingServer.blockedPIDs = [201]
        let waitingRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: waitingServer)
        await waitingRunner.runForTesting(.stopServer)
        check(waitingRunner.remainingApps.map(\.pid) == [201] && waitingRunner.hasError && waitingRunner.activeMode == nil, "Terminal quit confirmation is reported as pending")
        check(waitingServer.terminated.map(\.pid) == [200, 201] && !waitingRunner.isBusy, "Pending Stop Server does not force quit or repeat requests")

        let dockerOnly = FakeSystem()
        dockerOnly.processes = [serverApps[0]]
        let dockerOnlyRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: dockerOnly)
        await dockerOnlyRunner.runForTesting(.stopServer)
        check(dockerOnly.terminated.map(\.pid) == [200] && !dockerOnlyRunner.hasError, "Stop Server handles only one target running")

        let ownProcess = FakeSystem()
        ownProcess.processes = [AppProcess(pid: ownProcess.currentPID, name: "Docker", bundleIdentifier: AppTarget.docker.bundleIdentifier, path: AppTarget.docker.path, policy: 1)]
        let ownRunner = ModeRunner(settings: SettingsStore(defaults: nil), system: ownProcess)
        await ownRunner.runForTesting(.stopServer)
        check(ownProcess.terminated.isEmpty, "Stop Server never terminates its own process")

        let concurrentSystem = FakeSystem()
        let concurrent = ModeRunner(settings: SettingsStore(defaults: nil), system: concurrentSystem)
        concurrent.start(.code)
        concurrent.start(.game)
        while concurrent.isBusy { await Task.yield() }
        check(concurrentSystem.launches == defaults.code.map(\.id), "Rapid clicks do not overlap modes")

        print("\(count - failures.count)/\(count) checks passed")
        return failures.isEmpty
    }
}
