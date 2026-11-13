// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import Foundation

enum ModeError: LocalizedError {
    case missing(String), launch(String), timeout(String)
    var errorDescription: String? {
        switch self {
        case .missing(let name): return "ไม่พบ \(name) · เลือกแอปใหม่ในตั้งค่า"
        case .launch(let name): return "เปิด \(name) ไม่สำเร็จ"
        case .timeout(let name): return "\(name) ใช้เวลาเปิดนานเกินไป ลองอีกครั้ง"
        }
    }
}

@MainActor
protocol ModeSystem: AnyObject {
    var currentPID: Int32 { get }
    func isAvailable(_ target: AppTarget) -> Bool
    func launch(_ target: AppTarget, opening webpage: URL?) async throws -> AppProcess
    func activate(_ app: AppProcess) -> Bool
    func runningApps() -> [AppProcess]
    func terminate(_ app: AppProcess) -> Bool
    func runServerStopScript(at path: String) async throws
    func stopDockerDesktop() async throws
    func wait(milliseconds: UInt64) async
}

extension ModeSystem {
    func launch(_ target: AppTarget) async throws -> AppProcess {
        try await launch(target, opening: nil)
    }
}

@MainActor
final class MacSystem: ModeSystem {
    private let commands = NativeCommandRunner()
    var currentPID: Int32 { ProcessInfo.processInfo.processIdentifier }
    func isAvailable(_ target: AppTarget) -> Bool { target.resolvedURL != nil }

    func launch(_ target: AppTarget, opening webpage: URL? = nil) async throws -> AppProcess {
        guard let url = target.resolvedURL else { throw ModeError.missing(target.name) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        config.promptsUserIfNeeded = false
        config.addsToRecentItems = false
        if let identifier = target.bundleIdentifier {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: identifier)
        }
        return try await withCheckedThrowingContinuation { continuation in
            // The timeout and workspace callback both run their completion gate on the main queue.
            var completed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                guard !completed else { return }
                completed = true
                continuation.resume(throwing: ModeError.timeout(target.name))
            }
            let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { app, error in
                DispatchQueue.main.async {
                    guard !completed else { return }
                    completed = true
                    if let app { continuation.resume(returning: AppProcess(app)) }
                    else { continuation.resume(throwing: error ?? ModeError.launch(target.name)) }
                }
            }
            if let webpage {
                NSWorkspace.shared.open([webpage], withApplicationAt: url, configuration: config, completionHandler: completion)
            } else {
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
            }
        }
    }

    func activate(_ app: AppProcess) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: app.pid), !running.isTerminated else { return false }
        running.unhide()
        NSApp.yieldActivation(to: running)
        return running.activate(from: .current, options: [.activateAllWindows])
    }

    func runningApps() -> [AppProcess] {
        NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map(AppProcess.init)
    }

    func terminate(_ app: AppProcess) -> Bool {
        NSRunningApplication(processIdentifier: app.pid)?.terminate() ?? false
    }

    func runServerStopScript(at path: String) async throws {
        guard FileManager.default.isReadableFile(atPath: path) else { throw ShutdownError.missingScript }
        let request = CommandRequest(executable: "/bin/zsh", arguments: [path], workingDirectory: URL(fileURLWithPath: path).deletingLastPathComponent().path)
        let result = try await commands.run(request)
        guard result.status == 0 else { throw ShutdownError.scriptFailed(result.status) }
    }

    func stopDockerDesktop() async throws {
        guard let appURL = AppTarget.docker.resolvedURL else { return }
        let executable = appURL.appendingPathComponent("Contents/Resources/bin/docker").path
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw ShutdownError.dockerUnavailable }
        try await DockerDesktopStopper(commands: commands, appDirectory: appURL.path).stop(using: executable)
    }

    func wait(milliseconds: UInt64) async { try? await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
}

@MainActor
final class ModeRunner: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var activeMode: Mode?
    @Published private(set) var status = "เลือกโหมด แล้วเริ่มได้เลย"
    @Published private(set) var detail = "แอปสุดท้ายในลำดับจะอยู่ด้านหน้าสุด"
    @Published private(set) var hasError = false
    @Published private(set) var remainingApps: [AppProcess] = []
    let settings: SettingsStore
    let system: ModeSystem
    var onStart: (() -> Void)?
    var onStateChange: (() -> Void)?

    init(settings: SettingsStore, system: ModeSystem) {
        self.settings = settings
        self.system = system
    }

    func start(_ mode: Mode) {
        guard !isBusy else { return }
        // Set synchronously so two clicks cannot queue overlapping switches.
        isBusy = true
        hasError = false
        remainingApps = []
        status = "กำลังเข้า \(mode.title)…"
        detail = ""
        onStart?()
        onStateChange?()
        Task { await perform(mode) }
    }

    func runForTesting(_ mode: Mode) async {
        guard !isBusy else { return }
        isBusy = true
        await perform(mode)
    }

    private func perform(_ mode: Mode) async {
        defer { isBusy = false; onStateChange?() }
        activeMode = nil
        if mode == .stopServer {
            await stopServer()
            return
        }
        if mode == .clear {
            await clearApps()
            return
        }
        let targets = settings.configuration[mode]
        guard !targets.isEmpty else {
            hasError = true
            status = "ยังไม่มีแอปใน \(mode.title)"
            detail = "เพิ่มแอปได้ที่ตั้งค่าโหมด"
            return
        }
        let missing = targets.filter { !system.isAvailable($0) }
        guard missing.isEmpty else {
            hasError = true
            status = "ไม่พบแอป: \(missing.map(\.name).joined(separator: ", "))"
            detail = "เปิดตั้งค่าโหมดเพื่อเลือกตำแหน่งแอปใหม่"
            return
        }
        do {
            var lastApp: AppProcess?
            for (index, target) in targets.enumerated() {
                status = "เปิด \(target.name) · \(index + 1)/\(targets.count)"
                let webpage = mode == .study && target.bundleIdentifier == AppTarget.firefox.bundleIdentifier
                    ? URL(string: "https://www.mycourseville.com/") : nil
                let launched = try await system.launch(target, opening: webpage)
                lastApp = launched
                await system.wait(milliseconds: 650)
            }
            if let lastApp {
                let activated = system.activate(lastApp)
                await system.wait(milliseconds: 900)
                let finalActivated = system.activate(lastApp)
                if !activated && !finalActivated {
                    hasError = true
                    status = "เปิดแอปครบแล้ว แต่ยก \(lastApp.name) ขึ้นหน้าไม่ได้"
                    detail = "คลิกแอปใน Dock เพื่อสลับไปด้านหน้า"
                    activeMode = nil
                    return
                }
            }
            activeMode = mode
            status = "\(mode.title) พร้อมแล้ว"
            detail = "\(targets.last?.name ?? "แอปสุดท้าย") อยู่ด้านหน้าสุด"
            hasError = false
        } catch {
            hasError = true
            activeMode = nil
            status = error.localizedDescription
            detail = "แอปที่เปิดไปแล้วจะยังเปิดอยู่ · ลองเลือกโหมดอีกครั้ง"
        }
    }

    private func clearApps() async {
        let candidates = system.runningApps().filter { app in
            QuitPolicy.includes(app, currentPID: system.currentPID, menuBarApps: settings.configuration.includeMenuBarApps)
        }
        status = "กำลังปิด \(candidates.count) แอป…"
        detail = "แอปอาจขอยืนยันการปิดหรือบันทึกงานก่อนปิด"
        for app in candidates { _ = system.terminate(app) }
        var remaining = candidates
        for _ in 0..<60 {
            let pids = Set(system.runningApps().map(\.pid))
            remaining = candidates.filter { pids.contains($0.pid) }
            if remaining.isEmpty { break }
            await system.wait(milliseconds: 250)
        }
        let livePIDs = Set(system.runningApps().map(\.pid))
        remaining = candidates.filter { livePIDs.contains($0.pid) }
        remainingApps = remaining
        if remaining.isEmpty {
            activeMode = .clear
            status = "Clear Mode พร้อมแล้ว"
            detail = candidates.isEmpty ? "ไม่มีแอปที่ต้องปิด" : "ปิดแล้ว \(candidates.count) แอป · พื้นที่พร้อมเริ่มใหม่"
            hasError = false
        } else {
            activeMode = nil
            hasError = true
            status = "ยังเปิดอยู่ \(remaining.count) แอป"
            detail = "อาจรอยืนยันหรือบันทึกงาน · คลิกชื่อแอปด้านล่าง"
        }
    }

    private func stopServer() async {
        var errors: [String] = []
        if let script = settings.serverStopScriptPath {
            status = "กำลังหยุดงานเซิร์ฟเวอร์เบื้องหลัง…"
            detail = "รอสคริปต์หยุดเซิร์ฟเวอร์ทำงานเสร็จ"
            do { try await system.runServerStopScript(at: script) }
            catch { errors.append(error.localizedDescription) }
        }
        status = "กำลังปิด Docker Desktop…"
        detail = "กำลังหยุด Docker engine และตรวจสถานะ"
        do { try await system.stopDockerDesktop() }
        catch { errors.append(error.localizedDescription) }

        status = "กำลังปิด Terminal…"
        let terminals = system.runningApps().filter {
            $0.pid > 0 && $0.pid != system.currentPID && $0.bundleIdentifier == AppTarget.terminal.bundleIdentifier
        }
        for terminal in terminals { _ = system.terminate(terminal) }
        for _ in 0..<60 {
            let livePIDs = Set(system.runningApps().map(\.pid))
            if !terminals.contains(where: { livePIDs.contains($0.pid) }) { break }
            await system.wait(milliseconds: 250)
        }
        let livePIDs = Set(system.runningApps().map(\.pid))
        remainingApps = terminals.filter { livePIDs.contains($0.pid) }
        if !remainingApps.isEmpty { errors.append("Terminal ยังรอยืนยันการปิด · คลิกชื่อแอปด้านล่าง") }
        hasError = !errors.isEmpty
        if errors.isEmpty {
            activeMode = .stopServer
            status = "Stop Server เสร็จแล้ว"
            detail = settings.serverStopScriptPath == nil ? "Docker Desktop และ Terminal ปิดแล้ว" : "หยุดงานเซิร์ฟเวอร์แล้ว · Docker Desktop และ Terminal ปิดแล้ว"
        } else {
            status = "Stop Server ยังไม่เสร็จ"
            detail = errors.joined(separator: " · ")
        }
    }

    func showRemaining(_ app: AppProcess) {
        onStart?()
        _ = system.activate(app)
    }
}
