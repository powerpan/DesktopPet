//
// ChatAttachmentStorage.swift
// 会话消息附件落盘（Application Support），避免 UserDefaults 膨胀。
//

import Foundation

struct ChatAttachmentRef: Identifiable, Equatable, Codable {
    var id: UUID
    var filename: String
    var mimeType: String
    var byteCount: Int
}

enum ChatAttachmentStorage {
    private static let folderName = "ChatAttachments"

    static func baseDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DesktopPet", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func directory(for messageId: UUID) throws -> URL {
        let d = try baseDirectory().appendingPathComponent(messageId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func write(messageId: UUID, ref: ChatAttachmentRef, data: Data) throws {
        let dir = try directory(for: messageId)
        let url = dir.appendingPathComponent(ref.id.uuidString)
        try data.write(to: url, options: .atomic)
    }

    static func read(messageId: UUID, ref: ChatAttachmentRef) -> Data? {
        guard let dir = try? directory(for: messageId) else { return nil }
        let url = dir.appendingPathComponent(ref.id.uuidString)
        return try? Data(contentsOf: url)
    }

    static func deleteAll(messageId: UUID) {
        guard let base = try? baseDirectory() else { return }
        let dir = base.appendingPathComponent(messageId.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    static func deleteAttachments(for messages: [ChatMessage]) {
        for m in messages {
            if !m.attachments.isEmpty {
                deleteAll(messageId: m.id)
            }
        }
    }
}
