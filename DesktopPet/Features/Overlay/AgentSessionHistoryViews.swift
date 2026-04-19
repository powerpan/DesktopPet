//
// AgentSessionHistoryViews.swift
// 设置内：正式会话频道列表、单频道消息详情、条件触发旁白历史。
//

import AppKit
import SwiftUI

/// 旁白历史 / 模型请求列表中按「发送类型」（触发器种类）筛选。
enum TriggerSendKindListFilter: Hashable {
    case all
    case kind(AgentTriggerKind)
}

// MARK: - 正式会话频道

struct ConversationChannelsManagerSheet: View {
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(session.channels) { ch in
                NavigationLink {
                    ConversationChannelDetailView(channelId: ch.id, isPresented: $isPresented)
                        .environmentObject(session)
                        .environmentObject(routeBus)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ch.title)
                            .font(.headline)
                        Text("\(ch.messages.count) 条消息 · 更新于 \(Self.shortDate(ch.updatedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("正式会话频道")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}

struct ConversationChannelDetailView: View {
    let channelId: UUID
    @Binding var isPresented: Bool
    @EnvironmentObject private var session: AgentSessionStore
    @EnvironmentObject private var routeBus: AppRouteBus

    private var channel: ChatChannel? {
        session.channels.first { $0.id == channelId }
    }

    var body: some View {
        Group {
            if let ch = channel {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(ch.messages) { m in
                            historyBubble(m)
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        routeBus.presentChatContinuingChannel(id: channelId)
                        isPresented = false
                    } label: {
                        Label("在此频道继续聊天", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .background(.bar)
                }
                .navigationTitle(ch.title)
            } else {
                ContentUnavailableView("找不到该频道", systemImage: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder
    private func historyBubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case "system":
            Text(m.content)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(InlineMarkdownBubble.attributedDisplayString(m.content))
                    .font(.body)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        default:
            HStack {
                Text(InlineMarkdownBubble.attributedDisplayString(m.content))
                    .font(.body)
                    .padding(10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - 触发旁白历史中的截图预览

private struct TriggerSpeechSnapshotThumbnail: View {
    let storedFileName: String?

    var body: some View {
        Group {
            if let name = storedFileName,
               let url = TriggerSpeechSnapshotStorage.fileURL(storedFileName: name),
               let img = NSImage(contentsOf: url) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("随请求发送的截图（本地）")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Application Support → DesktopPet → TriggerSnapshots → \(name)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - 条件触发旁白历史

struct TriggerSpeechHistoryListSheet: View {
    @EnvironmentObject private var session: AgentSessionStore
    @Binding var isPresented: Bool
    @State private var sendKindFilter: TriggerSendKindListFilter = .all

    private var filteredRecords: [TriggerSpeechRecord] {
        switch sendKindFilter {
        case .all:
            return session.triggerHistory.records
        case .kind(let k):
            return session.triggerHistory.records.filter { $0.triggerKind == k }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.triggerHistory.records.isEmpty {
                    ContentUnavailableView("暂无记录", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "该发送类型下暂无记录",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("请切换筛选或选择「全部」。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredRecords) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(r.triggerKind.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                Spacer()
                                Text(Self.shortDate(r.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            TriggerSpeechSnapshotThumbnail(storedFileName: r.userRequestSnapshotFileName)
                            if let req = r.userPromptSent, !req.isEmpty {
                                Text("发给模型的 user（纯文本部分）")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(req)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(4)
                            }
                            Text(InlineMarkdownBubble.attributedDisplayString(r.text))
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("条件触发旁白历史")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("发送类型", selection: $sendKindFilter) {
                        Text("全部").tag(TriggerSendKindListFilter.all)
                        ForEach(AgentTriggerKind.allCases) { kind in
                            Text(kind.displayName).tag(TriggerSendKindListFilter.kind(kind))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }

    fileprivate static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: d)
    }
}

// MARK: - 触发器发给模型的 user 请求历史

struct TriggerUserPromptHistorySheet: View {
    @EnvironmentObject private var session: AgentSessionStore
    @Binding var isPresented: Bool
    @State private var sendKindFilter: TriggerSendKindListFilter = .all

    private var allPromptEntries: [TriggerSpeechRecord] {
        session.triggerHistory.records.filter { ($0.userPromptSent?.isEmpty == false) }
    }

    private var entries: [TriggerSpeechRecord] {
        switch sendKindFilter {
        case .all:
            return allPromptEntries
        case .kind(let k):
            return allPromptEntries.filter { $0.triggerKind == k }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allPromptEntries.isEmpty {
                    ContentUnavailableView(
                        "暂无请求记录",
                        systemImage: "text.document",
                        description: Text("仅「经过大模型」的条件旁白会保存本条。气泡测试不请求模型；若升级前产生的旧旁白历史也可能没有请求正文。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "该发送类型下暂无请求",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("请切换筛选或选择「全部」。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(entries) { r in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(r.triggerKind.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                Spacer()
                                Text(TriggerSpeechHistoryListSheet.shortDate(r.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            TriggerSpeechSnapshotThumbnail(storedFileName: r.userRequestSnapshotFileName)
                            if let p = r.userPromptSent {
                                Text(p)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            Divider()
                            Text("模型返回的旁白（同一条记录）")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(InlineMarkdownBubble.attributedDisplayString(r.text))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("触发器发给模型的请求")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("发送类型", selection: $sendKindFilter) {
                        Text("全部").tag(TriggerSendKindListFilter.all)
                        ForEach(AgentTriggerKind.allCases) { kind in
                            Text(kind.displayName).tag(TriggerSendKindListFilter.kind(kind))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }
}

enum DesktopPetNotificationUserInfoKey {
    static let channelId = "channelId"
    /// `AgentTriggerRule` 的 JSON 字符串（与 `JSONEncoder` 默认输出一致）。
    static let triggerRuleJSON = "triggerRuleJSON"
    /// 饲养互动旁白：由应用拼好的多行说明，替换模板中的 `{careContext}`。
    static let careContext = "careContext"
    /// 打开智能体工作台时要选中的分区索引（Int）：兼容 **旧版 7 Tab**（0=连接…6=集成）；经 `AppCoordinator` 桥接映射为当前五分区（连接/对话/陪伴/自动化/集成）。
    static let agentSettingsTabIndex = "agentSettingsTabIndex"
    static let conversationAppendChannelId = "conversationAppendChannelId"
    static let conversationAppendMessageId = "conversationAppendMessageId"
    static let conversationAppendRole = "conversationAppendRole"
    static let conversationAppendContent = "conversationAppendContent"
    /// `"local"` 或 `"slack"`。
    static let conversationAppendOrigin = "conversationAppendOrigin"
    static let conversationAppendSlackTs = "conversationAppendSlackTs"
    static let conversationAppendSlackChannelId = "conversationAppendSlackChannelId"
}
