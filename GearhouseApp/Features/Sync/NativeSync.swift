import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeSync: View {
    @EnvironmentObject private var store: NativeStore
    @State private var key = ""
    @State private var connecting = false
    @State private var connectionOpen = false
    @State private var historyOpen = false
    @State private var from = NativeDate.parse("2024-01-01")
    @State private var to = Date()
    @State private var failure: String?
    @FocusState private var enteringKey: Bool

    private var syncError: String? {
        let message = store.state["autoSync"]["error"].text
        return message.isEmpty ? nil : UserFacingError.text(message)
    }
    private var records: [Value] { Array(store.state["syncLog"].array.prefix(20)) }
    private var lastSuccess: Date? {
        let value = store.state["autoSync"]["lastSuccess"].text, formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
    private var connectionLabel: String {
        guard store.connected else { return "尚未连接" }
        let name = store.state["account"]["name"].text
        return name.isEmpty ? "已连接" : name
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: store.connected ? "checkmark.icloud" : "icloud")
                        .font(.title2).foregroundStyle(NativeAppearance.accent)
                        .frame(width: 40, height: 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Intervals.icu").font(.headline)
                        Text(connectionLabel)
                            .font(.subheadline).foregroundStyle(NativeAppearance.secondaryText)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.vertical, 6).accessibilityElement(children: .combine)
                DisclosureGroup(store.connected ? "管理连接" : "连接账户", isExpanded: $connectionOpen) {
                    SecureField(store.connected ? "替换 API Key" : "API Key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($enteringKey).submitLabel(.done)
                        .accessibilityIdentifier("sync-api-key")
                    if connecting { Label { Text("连接中…") } icon: { ProgressView() } }
                    else {
                        Button(store.connected ? "更新连接" : "连接") { connectAccount() }
                            .disabled(store.busy || key.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                            .accessibilityIdentifier("sync-connect")
                    }
                    Link(destination: URL(string: "https://intervals.icu/settings")!) {
                        Label("Intervals.icu 设置", systemImage: "arrow.up.right.square")
                    }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.circle").foregroundStyle(NativeAppearance.dangerText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.disabled(connecting)
            }

            Section("活动同步") {
                Toggle("自动同步", isOn: Binding(get: { store.state["autoSync"]["enabled"] != false }, set: store.setAutoSync))
                    .disabled(!store.connected || connecting).accessibilityIdentifier("sync-automatic")
                if store.busy {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("正在同步").font(.subheadline.weight(.medium))
                            Text(store.progress).font(.caption).foregroundStyle(NativeAppearance.secondaryText)
                        }.fixedSize(horizontal: false, vertical: true)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("sync-progress")
                    Button(store.stoppingSync ? "正在停止…" : "取消同步") { store.cancelSync() }
                        .disabled(store.stoppingSync).accessibilityIdentifier("sync-cancel")
                } else {
                    if store.refreshingGears {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在读取装备").fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                            .accessibilityIdentifier("sync-gear-refresh-progress")
                    }
                    LabeledContent("最近同步") {
                        if let lastSuccess { Text(lastSuccess, format: .dateTime.month().day().hour().minute()) }
                        else { Text("尚未同步").foregroundStyle(NativeAppearance.secondaryText) }
                    }
                    Button { store.startSync() } label: {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(store.connected && !connecting && !store.refreshingGears ? NativeAppearance.accent : NativeAppearance.secondaryText)
                    }
                        .disabled(!store.connected || connecting || store.refreshingGears).accessibilityIdentifier("sync-now")
                }
                if let syncError {
                    Label(syncError, systemImage: "exclamationmark.circle").foregroundStyle(NativeAppearance.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sync-error")
                }
                DisclosureGroup("历史补录", isExpanded: $historyOpen) {
                    DatePicker("开始日期", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("结束日期", selection: $to, in: from...Date(), displayedComponents: .date)
                    Button {
                        store.startSync(from: NativeDate.format(from, "yyyy-MM-dd"), to: NativeDate.format(to, "yyyy-MM-dd"))
                    } label: {
                        Label("读取活动", systemImage: "arrow.down.circle")
                            .foregroundStyle(store.connected && !store.busy && !connecting && !store.refreshingGears ? NativeAppearance.accent : NativeAppearance.secondaryText)
                    }
                        .disabled(!store.connected || store.busy || connecting || store.refreshingGears).accessibilityIdentifier("sync-history-load")
                }
            }

            Section {
                NavigationLink { NativeBackupSettings() } label: { Label("备份与恢复", systemImage: "externaldrive.badge.icloud") }
                    .accessibilityIdentifier("backup-settings")
            }

            if !records.isEmpty {
                Section("同步记录") {
                    ForEach(Array(records.enumerated()), id: \.offset) { _, row in buildRecord(row) }
                }
            }
        }
        .scrollContentBackground(.hidden).background(NativeAppearance.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("同步")
        .onAppear { if !store.connected { connectionOpen = true } }
        .onSubmit { enteringKey = false }
        .toolbar {
            if enteringKey {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { enteringKey = false } }
            }
        }
    }

    private func buildRecord(_ row: Value) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(formatDate(row["oldest"].text) + " – " + formatDate(row["newest"].text))
                .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { buildCounts(row) }
                VStack(alignment: .leading, spacing: 5) { buildCounts(row) }
            }.font(.caption).foregroundStyle(NativeAppearance.secondaryText)
            if row["unavailable"].integer > 0 {
                Label("\(row["unavailable"].integer) 条活动暂时无法读取", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(NativeAppearance.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }

    @ViewBuilder private func buildCounts(_ row: Value) -> some View {
        if row["added"].integer + row["updated"].integer + row["removed"].integer + row["unavailable"].integer == 0 { Text("没有变化") }
        else {
            if row["added"].integer > 0 { Text("新增 \(row["added"].integer)") }
            if row["updated"].integer > 0 { Text("更新 \(row["updated"].integer)") }
            if row["removed"].integer > 0 { Text("移除 \(row["removed"].integer)") }
        }
    }

    private func formatDate(_ value: String) -> String {
        guard !value.isEmpty else { return "—" }
        return NativeDate.format(NativeDate.parse(value), "yyyy/M/d")
    }

    private func connectAccount() {
        enteringKey = false; connecting = true; failure = nil
        let enteredKey = key
        Task {
            defer { connecting = false }
            do { try await store.connect(enteredKey); key = ""; connectionOpen = false }
            catch { failure = error.userFacingMessage }
        }
    }
}
