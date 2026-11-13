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
    func wait(milliseconds: UInt64) async
}

extension ModeSystem {
    func launch(_ target: AppTarget) async throws -> AppProcess {
        try await launch(target, opening: nil)
    }
}

@MainActor
final class MacSystem: ModeSystem {
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
        if mode.isQuitMode {
            await quitApps(for: mode)
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

    private func quitApps(for mode: Mode) async {
        let targetIDs = Set(settings.configuration[mode].compactMap(\.bundleIdentifier))
        let candidates = system.runningApps().filter { app in
            if mode == .stopServer {
                guard app.pid > 0, app.pid != system.currentPID,
                      let identifier = app.bundleIdentifier else { return false }
                return targetIDs.contains(identifier)
            }
            return QuitPolicy.includes(app, currentPID: system.currentPID, menuBarApps: settings.configuration.includeMenuBarApps)
        }
        status = mode == .stopServer ? "กำลังปิด Docker และ Terminal…" : "กำลังปิด \(candidates.count) แอป…"
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
            activeMode = mode
            if mode == .stopServer {
                status = "Stop Server เสร็จแล้ว"
                detail = candidates.isEmpty ? "Docker และ Terminal ปิดอยู่แล้ว" : "ปิดแล้ว \(candidates.count) แอป · Docker และ Terminal"
            } else {
                status = "Clear Mode พร้อมแล้ว"
                detail = candidates.isEmpty ? "ไม่มีแอปที่ต้องปิด" : "ปิดแล้ว \(candidates.count) แอป · พื้นที่พร้อมเริ่มใหม่"
            }
            hasError = false
        } else {
            activeMode = nil
            hasError = true
            status = "ยังเปิดอยู่ \(remaining.count) แอป"
            detail = "อาจรอยืนยันหรือบันทึกงาน · คลิกชื่อแอปด้านล่าง"
        }
    }

    func showRemaining(_ app: AppProcess) {
        onStart?()
        _ = system.activate(app)
    }
}
