//
// SlackRemoteClickSessionStore.swift
// 远程点屏会话：线程根 ts + 频道，单次点击、超时。
//

import CoreGraphics
import Foundation

@MainActor
final class SlackRemoteClickSessionStore {
    struct Session: Equatable {
        enum Status: String {
            case awaitingCoordinate
            case completed
            case expired
        }

        var channelId: String
        /// 线程根：用户发起 `!pet click` 的那条消息的 `ts`（Slack 线程子消息带相同 `thread_ts`）。
        var threadRootTs: String
        var status: Status
        var createdAt: Date
        var expiresAt: Date
        /// 主屏 `CGDisplayBounds` 在发起时的快照（Quartz 全局、左下原点）。
        var displayBounds: CGRect
        /// 发给用户的标尺图尺寸（像素，与 `overlayJPEG` 一致）。
        var imagePixelSize: CGSize
        /// 覆盖后的 JPEG（用于上传失败时本地不再保留引用，仅存尺寸即可；可选丢弃以省内存）。
        var overlayJPEG: Data?

        var key: String { "\(channelId)|\(threadRootTs)" }
    }

    private var sessions: [String: Session] = [:]
    private let ttlSeconds: TimeInterval = 300

    func allAwaitingKeys() -> [(channelId: String, threadRootTs: String)] {
        pruneExpired()
        return sessions.values.filter { $0.status == .awaitingCoordinate }.map { ($0.channelId, $0.threadRootTs) }
    }

    func session(channelId: String, threadRootTs: String) -> Session? {
        pruneExpired()
        return sessions["\(channelId)|\(threadRootTs)"]
    }

    func beginSession(
        channelId: String,
        threadRootTs: String,
        displayBounds: CGRect,
        imagePixelSize: CGSize,
        overlayJPEG: Data?
    ) {
        let now = Date()
        let s = Session(
            channelId: channelId,
            threadRootTs: threadRootTs,
            status: .awaitingCoordinate,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttlSeconds),
            displayBounds: displayBounds,
            imagePixelSize: imagePixelSize,
            overlayJPEG: overlayJPEG
        )
        sessions[s.key] = s
    }

    func complete(channelId: String, threadRootTs: String) {
        let k = "\(channelId)|\(threadRootTs)"
        guard var s = sessions[k] else { return }
        s.status = .completed
        s.overlayJPEG = nil
        sessions[k] = s
        sessions.removeValue(forKey: k)
    }

    func expire(channelId: String, threadRootTs: String) {
        let k = "\(channelId)|\(threadRootTs)"
        sessions.removeValue(forKey: k)
    }

    private func pruneExpired() {
        let now = Date()
        for (k, s) in sessions where s.expiresAt < now && s.status == .awaitingCoordinate {
            sessions.removeValue(forKey: k)
        }
    }
}
