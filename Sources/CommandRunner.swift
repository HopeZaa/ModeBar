// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import Foundation
import Darwin

struct CommandRequest: Equatable, Sendable {
    var executable: String
    var arguments: [String]
    var workingDirectory: String? = nil
    var timeout: TimeInterval = 120
}

struct CommandResult: Sendable {
    var status: Int32
    var output: String
}

enum ShutdownError: LocalizedError {
    case timeout, missingScript, scriptFailed(Int32), dockerUnavailable, dockerFailed, dockerStillRunning, dockerUnknown
    var errorDescription: String? {
        switch self {
        case .timeout: return "คำสั่งหยุดเซิร์ฟเวอร์ใช้เวลานานเกินไป"
        case .missingScript: return "ไม่พบสคริปต์หยุดเซิร์ฟเวอร์ · เลือกใหม่ในตั้งค่าโหมด"
        case .scriptFailed(let code): return "สคริปต์หยุดเซิร์ฟเวอร์ไม่สำเร็จ (รหัส \(code))"
        case .dockerUnavailable: return "ไม่พบ Docker Desktop CLI · ตรวจการติดตั้ง Docker Desktop"
        case .dockerFailed: return "Docker Desktop ปิดไม่สำเร็จ · ลอง Stop Server อีกครั้ง"
        case .dockerStillRunning: return "Docker Desktop ยังทำงานเบื้องหลัง · ยังยืนยันการปิดไม่ได้"
        case .dockerUnknown: return "ตรวจสถานะ Docker Desktop ไม่สำเร็จ · ยังยืนยันการปิดไม่ได้"
        }
    }
}

@MainActor
protocol CommandExecuting: AnyObject {
    func run(_ command: CommandRequest) async throws -> CommandResult
}

@MainActor
final class NativeCommandRunner: CommandExecuting {
    func run(_ command: CommandRequest) async throws -> CommandResult {
        try await Task.detached(priority: .utility) { try Self.execute(command) }.value
    }

    private nonisolated static func execute(_ command: CommandRequest) throws -> CommandResult {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("ModeBar-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: logURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: logURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        if let directory = command.workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        var environment = ProcessInfo.processInfo.environment
        let paths = ["/Applications/Docker.app/Contents/Resources/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = (paths + [environment["PATH"] ?? ""]).joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + command.timeout) == .timedOut {
            // Terminate only the command we started, and its group when Foundation isolated it.
            let pid = process.processIdentifier
            if process.isRunning {
                if getpgid(pid) == pid { _ = killpg(pid, SIGTERM) }
                else { process.terminate() }
            }
            if finished.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                if getpgid(pid) == pid { _ = killpg(pid, SIGKILL) }
                else { _ = kill(pid, SIGKILL) }
                _ = finished.wait(timeout: .now() + 2)
            }
            throw ShutdownError.timeout
        }
        try output.synchronize()
        let input = try FileHandle(forReadingFrom: logURL)
        defer { try? input.close() }
        let end = try input.seekToEnd()
        try input.seek(toOffset: end > 65_536 ? end - 65_536 : 0)
        let data = try input.read(upToCount: 65_536) ?? Data()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

@MainActor
final class DockerDesktopStopper {
    private let commands: CommandExecuting
    private let appDirectory: String
    private let pollDelay: UInt64
    init(commands: CommandExecuting, appDirectory: String, pollDelay: UInt64 = 500_000_000) {
        self.commands = commands
        self.appDirectory = appDirectory
        self.pollDelay = pollDelay
    }

    func isRunning(using executable: String) async throws -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: appDirectory)
        let pattern = "^(\(escaped)/Contents/MacOS/|\(escaped)/Contents/Resources/Docker Desktop[.]app/Contents/)"
        let processes = try await commands.run(CommandRequest(executable: "/usr/bin/pgrep", arguments: ["-f", pattern], timeout: 5))
        if processes.status == 0 { return true }
        guard processes.status == 1 else { throw ShutdownError.dockerUnknown }
        let engine = try await commands.run(CommandRequest(executable: executable, arguments: ["--context", "desktop-linux", "info", "--format", "{{.ServerVersion}}"], timeout: 15))
        return engine.status == 0
    }

    func stop(using executable: String) async throws {
        if try await !isRunning(using: executable) { return }
        // Docker Desktop's backend is not reliably represented as a normal NSRunningApplication.
        // Its supported shutdown command closes the engine and Desktop together, without --force.
        let result = try await commands.run(CommandRequest(executable: executable, arguments: ["desktop", "stop", "--timeout", "60"], timeout: 75))
        for attempt in 0..<10 {
            if try await !isRunning(using: executable) { return }
            if attempt < 9, pollDelay > 0 { try? await Task.sleep(nanoseconds: pollDelay) }
        }
        if result.status != 0 { throw ShutdownError.dockerFailed }
        throw ShutdownError.dockerStillRunning
    }
}
