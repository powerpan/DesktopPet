//
// SlackRemoteClickSessionStore.swift
// 远程点屏会话：线程根 ts + 频道；支持多轮「截屏 → 坐标 → 点击 → 询问是否继续」。
//

import CoreGraphics
import Foundation

@MainActor
final class SlackRemoteClickSessionStore {
    struct Session: Equatable {
        enum Status: String {
            /// 等待用户回复坐标。
            case awaitingCoordinate
            /// 已成功点击一轮，等待用户回复「继续」或「结束」。
            case awaitingContinue
        }

        var channelId: String
        /// 线程根：用户发起命令的那条消息的 `ts`。
        var threadRootTs: String
        var status: Status
        var createdAt: Date
        var expiresAt: Date
        var displayBounds: CGRect
        var imagePixelSize: CGSize
        var overlayJPEG: Data?

        var key: String { "\(channelId)|\(threadRootTs)" }
    }

    private var sessions: [String: Session] = [:]
    private let ttlSeconds: TimeInterval = 300

    /// 需要轮询 `conversations.replies` 的会话（等坐标或等「继续」）。
    func allAwaitingKeys() -> [(channelId: String, threadRootTs: String)] {
        pruneExpired()
        return sessions.values
            .filter { $0.status == .awaitingCoordinate || $0.status == .awaitingContinue }
            .map { ($0.channelId, $0.threadRootTs) }
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

    /// 一轮点击成功后进入「是否继续」。
    func setAwaitingContinue(channelId: String, threadRootTs: String) {
        let k = "\(channelId)|\(threadRootTs)"
        guard var s = sessions[k] else { return }
        s.status = .awaitingContinue
        s.overlayJPEG = nil
        sessions[k] = s
    }

    /// 用户确认继续：刷新几何与超时，重新等待坐标。
    func resumeAwaitingCoordinate(
        channelId: String,
        threadRootTs: String,
        displayBounds: CGRect,
        imagePixelSize: CGSize
    ) {
        let k = "\(channelId)|\(threadRootTs)"
        guard var s = sessions[k], s.status == .awaitingContinue else { return }
        let now = Date()
        s.status = .awaitingCoordinate
        s.displayBounds = displayBounds
        s.imagePixelSize = imagePixelSize
        s.expiresAt = now.addingTimeInterval(ttlSeconds)
        s.overlayJPEG = nil
        sessions[k] = s
    }

    func complete(channelId: String, threadRootTs: String) {
        let k = "\(channelId)|\(threadRootTs)"
        sessions.removeValue(forKey: k)
    }

    func expire(channelId: String, threadRootTs: String) {
        complete(channelId: channelId, threadRootTs: threadRootTs)
    }

    private func pruneExpired() {
        let now = Date()
        for (k, s) in sessions where s.expiresAt < now {
            sessions.removeValue(forKey: k)
        }
    }
}
