//
// AgentSessionHistoryViews.swift
// 设置内：正式会话频道列表、单频道消息详情、条件触发旁白历史。
//

import SwiftUI

// MARK: - 正式会话频道

struct ConversationChannelsManagerSheet: View {
    @EnvironmentObject private var session: AgentSessionStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(session.channels) { ch in
                NavigationLink {
                    ConversationChannelDetailView(channelId: ch.id, isPresented: $isPresented)
                        .environmentObject(session)
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
                        NotificationCenter.default.post(
                            name: .desktopPetPresentChatContinuingChannel,
                            object: nil,
                            userInfo: [DesktopPetNotificationUserInfoKey.channelId: channelId.uuidString]
                        )
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
                Text(m.content)
                    .font(.body)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        default:
            HStack {
                Text(m.content)
                    .font(.body)
                    .padding(10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - 条件触发旁白历史

struct TriggerSpeechHistoryListSheet: View {
    @EnvironmentObject private var session: AgentSessionStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Group {
                if session.triggerHistory.records.isEmpty {
                    ContentUnavailableView("暂无记录", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(session.triggerHistory.records) { r in
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
                            Text(r.text)
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
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: d)
    }
}

enum DesktopPetNotificationUserInfoKey {
    static let channelId = "channelId"
    /// `TestBubbleSample.rawValue`（`short` / `long`）
    static let testBubbleSample = "sample"
}
