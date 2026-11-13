// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 HopeZaa

import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

extension Mode {
    var color: Color {
        switch self {
        case .code: return Color(red: 0.42, green: 0.82, blue: 0.97)
        case .study: return Color(red: 0.72, green: 0.65, blue: 1)
        case .game: return Color(red: 0.52, green: 0.89, blue: 0.69)
        case .stopServer: return Color(red: 1, green: 0.78, blue: 0.42)
        case .clear: return Color(red: 1, green: 0.68, blue: 0.57)
        }
    }
}

struct AppIcon: View {
    let target: AppTarget
    var size: CGFloat = 21
    var body: some View {
        Group {
            if let url = target.resolvedURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .help(target.name)
        .accessibilityLabel(target.name)
    }
}

struct ModeButton: View {
    let mode: Mode
    let apps: [AppTarget]
    let selected: Bool
    let busy: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(mode.color)
                    .frame(width: 46, height: 46)
                    .background(mode.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(mode.title).font(.system(size: 15, weight: .semibold))
                        if selected {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(mode.color)
                        }
                    }
                    if mode == .clear {
                        Text("ปิดแอปทั้งหมดที่กำลังทำงาน")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if mode == .stopServer {
                        HStack(spacing: 5) {
                            ForEach(apps) { AppIcon(target: $0, size: 17) }
                            Text("ปิด Docker และ Terminal")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(apps.prefix(5).enumerated()), id: \.element.id) { index, app in
                                if index > 0 {
                                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.tertiary)
                                }
                                AppIcon(target: app, size: 17)
                            }
                            if apps.count > 5 { Text("+\(apps.count - 5)").font(.system(size: 10)) }
                            if let last = apps.last {
                                Text(last.name + " ด้านหน้า")
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            } else {
                                Text("เพิ่มแอปในตั้งค่า").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: mode == .stopServer ? "stop.circle" : "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovered ? mode.color : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(hovered ? mode.color.opacity(0.11) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? mode.color.opacity(0.45) : Color.white.opacity(hovered ? 0.15 : 0.065), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .onHover { hovered = $0 }
        .help(mode == .clear ? "ปิดแอปทั้งหมด ยกเว้น Finder และ ModeBar · แอปอาจขอให้บันทึกงาน" : mode == .stopServer ? "ปิดเฉพาะ Docker และ Terminal · แอปอาจขอให้ยืนยันก่อนปิด" : apps.map(\.name).joined(separator: " → "))
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode == .clear ? "ปิดทุกแอปที่เปิดอยู่" : mode == .stopServer ? "ปิดเฉพาะ Docker และ Terminal" : apps.map(\.name).joined(separator: ", "))
    }
}

struct MenuPanel: View {
    @ObservedObject var runner: ModeRunner
    @ObservedObject var settings: SettingsStore
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 24)).foregroundStyle(Color(red: 0.64, green: 0.8, blue: 1))
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ModeBar").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("พื้นที่ของคุณ ในโหมดที่ใช่").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if runner.isBusy {
                    ProgressView().controlSize(.small).accessibilityLabel("กำลังเปลี่ยนโหมด")
                } else {
                    Text("\(runner.activeMode?.rawValue.uppercased() ?? "READY")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2).foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white.opacity(0.05), in: Capsule())
                }
            }
            .padding(.bottom, 4)

            HStack {
                Text("เลือกโหมดของคุณ").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text("คลิกเดียว พร้อมเริ่ม").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            VStack(spacing: 8) {
                ForEach([Mode.code, .study, .game]) { mode in
                    ModeButton(mode: mode, apps: settings.configuration[mode], selected: runner.activeMode == mode,
                               busy: runner.isBusy) { runner.start(mode) }
                }
            }
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.vertical, 1)
            VStack(spacing: 8) {
                ModeButton(mode: .stopServer, apps: settings.configuration[.stopServer], selected: runner.activeMode == .stopServer,
                           busy: runner.isBusy) { runner.start(.stopServer) }
                ModeButton(mode: .clear, apps: [], selected: runner.activeMode == .clear, busy: runner.isBusy) { runner.start(.clear) }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: runner.hasError ? "exclamationmark.circle" : "circle.fill")
                        .font(.system(size: runner.hasError ? 12 : 6))
                        .foregroundStyle(runner.hasError ? Color.orange : Color.green.opacity(0.8))
                        .frame(width: 13, height: 16)
                    Text(runner.status).font(.system(size: 11, weight: .medium)).lineLimit(2)
                }
                Text(runner.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).padding(.leading, 20)
                if !runner.remainingApps.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(runner.remainingApps) { app in
                                Button(app.name + " ↗") { runner.showRemaining(app) }
                                    .buttonStyle(.link).font(.system(size: 11))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 55).padding(.leading, 20)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 45, alignment: .topLeading)
            .padding(10).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))

            HStack {
                Button(action: openSettings) {
                    Label("ตั้งค่าโหมด", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(runner.isBusy)
                Spacer()
                Button(action: quit) {
                    Image(systemName: "power").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("ออกจาก ModeBar").disabled(runner.isBusy)
            }.padding(.horizontal, 3)
        }
        .padding(17)
        .frame(width: 392)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.18), Color(red: 0.075, green: 0.085, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }
}

@MainActor
final class LoginSettings: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var message = ""

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            message = "อนุญาต ModeBar ใน System Settings → General → Login Items"
        }
    }

    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = ""
        } catch { message = error.localizedDescription }
        refresh()
    }
}

struct SettingsPanel: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var login = LoginSettings()
    @State private var selectedMode: Mode = .code
    @State private var pickerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ปรับโหมดให้เป็นของคุณ").font(.system(size: 24, weight: .bold))
                    Text("เปิดแอปตามลำดับจากบนลงล่าง · แอปสุดท้ายจะอยู่ด้านหน้าสุด")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 30)).foregroundStyle(.cyan)
            }
            Picker("โหมด", selection: $selectedMode) {
                ForEach([Mode.code, .study, .game]) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden()

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(settings.configuration[selectedMode].enumerated()), id: \.element.id) { index, target in
                        HStack(spacing: 12) {
                            Text(String(index + 1)).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary).frame(width: 18)
                            AppIcon(target: target, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name).font(.system(size: 13, weight: .medium))
                                Text(target.resolvedURL == nil ? "ไม่พบแอป · ลบแล้วเลือกใหม่" : target.path)
                                    .font(.system(size: 10)).foregroundStyle(target.resolvedURL == nil ? Color.orange : Color.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 3)
                            if index == settings.configuration[selectedMode].count - 1 {
                                Text("ด้านหน้าสุด").font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(selectedMode.color).padding(5)
                                    .background(selectedMode.color.opacity(0.1), in: Capsule())
                            }
                            Button { settings.move(target, in: selectedMode, offset: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0).help("เลื่อนขึ้น").accessibilityLabel("เลื่อน \(target.name) ขึ้น")
                            Button { settings.move(target, in: selectedMode, offset: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == settings.configuration[selectedMode].count - 1).help("เลื่อนลง").accessibilityLabel("เลื่อน \(target.name) ลง")
                            Button { settings.remove(target, from: selectedMode) } label: { Image(systemName: "minus.circle") }
                                .help("ลบออกจากโหมด").accessibilityLabel("ลบ \(target.name)")
                        }
                        .buttonStyle(.borderless)
                        .padding(11).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                    }
                    if settings.configuration[selectedMode].isEmpty {
                        Text("เพิ่มแอปแรกของโหมดนี้").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90)
                    }
                }
            }.frame(minHeight: 150, maxHeight: .infinity)
            HStack {
                Button { chooseApplications() } label: { Label("เพิ่มแอป…", systemImage: "plus") }
                Spacer()
                Button("คืนค่าโหมดนี้") { settings.configuration[selectedMode] = Configuration()[selectedMode] }
                    .foregroundStyle(.secondary)
            }
            if let error = pickerError ?? settings.persistenceError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("เปิด ModeBar อัตโนมัติเมื่อเข้าสู่ระบบ", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                Toggle("Clear Mode ปิดแอปบนแถบเมนูด้วย", isOn: $settings.configuration.includeMenuBarApps)
                Text("Clear Mode เว้น Finder และ ModeBar ไว้ · แอปที่มีงานค้างอาจขอบันทึกก่อนปิด")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("การเลือก Code, Study หรือ Game จะเปิดแอปในรายการ และเก็บแอปอื่นที่เปิดอยู่ไว้")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !login.message.isEmpty {
                    HStack {
                        Text(login.message).font(.system(size: 11)).foregroundStyle(.orange)
                        Button("เปิด Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }.font(.system(size: 12))
            HStack {
                Text("ModeBar 1.1 · Made for your Mac").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(25).frame(minWidth: 660, minHeight: 595)
        .background(Color(red: 0.10, green: 0.115, blue: 0.15))
        .preferredColorScheme(.dark)
        .onAppear { login.refresh() }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "เพิ่มแอปใน \(selectedMode.title)"
        panel.message = "เลือกแอปที่ต้องการเปิดในโหมดนี้"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard url.pathExtension.lowercased() == "app", Bundle(url: url)?.executableURL != nil else {
                pickerError = "เลือกไฟล์แอป .app ที่เปิดใช้งานได้"
                continue
            }
            let target = AppTarget(url: url)
            guard target.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            settings.add(target, to: selectedMode)
        }
    }
}
