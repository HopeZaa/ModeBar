// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import Foundation

@MainActor
private final class FixtureSystem: ModeSystem {
    let mac = MacSystem()
    let allowed = Set(["local.ModeBarFixture.Regular", "local.ModeBarFixture.Accessory"])
    var terminated: [AppProcess] = []
    var currentPID: Int32 { mac.currentPID }
    func isAvailable(_ target: AppTarget) -> Bool { mac.isAvailable(target) }
    func launch(_ target: AppTarget, opening webpage: URL?) async throws -> AppProcess {
        try await mac.launch(target, opening: webpage)
    }
    func activate(_ app: AppProcess) -> Bool { mac.activate(app) }
    func runningApps() -> [AppProcess] { mac.runningApps().filter { allowed.contains($0.bundleIdentifier ?? "") } }
    func terminate(_ app: AppProcess) -> Bool {
        guard allowed.contains(app.bundleIdentifier ?? "") else { fatalError("Only disposable fixtures may be closed") }
        terminated.append(app)
        return mac.terminate(app)
    }
    func wait(milliseconds: UInt64) async { await mac.wait(milliseconds: milliseconds) }
}

@main
enum VerifyClear {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let paths = Array(CommandLine.arguments.dropFirst())
        precondition(paths.count == 2)
        Task {
            let system = FixtureSystem()
            do {
                for path in paths {
                    let target = AppTarget(url: URL(fileURLWithPath: path))
                    precondition(system.allowed.contains(target.bundleIdentifier ?? ""))
                    _ = try await system.launch(target)
                }
                await system.wait(milliseconds: 500)
                let candidates = system.runningApps()
                precondition(candidates.count == 2)
                precondition(Set(candidates.map(\.policy)) == [0, 1])
                let runner = ModeRunner(settings: SettingsStore(defaults: nil), system: system)
                await runner.runForTesting(.clear)
                let success = !runner.hasError && system.runningApps().isEmpty && system.terminated.count == 2
                print("CLEAR_FIXTURES=\(candidates.count) TERMINATED=\(system.terminated.count) REMAINING=\(system.runningApps().count) STATUS=\(runner.status)")
                exit(success ? 0 : 1)
            } catch {
                for fixture in system.runningApps() { _ = system.terminate(fixture) }
                print("Fixture test failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        application.run()
    }
}
