//
// TriggerSpeechSnapshotStorage.swift
// 条件触发旁白随请求附带的截图：存于 Application Support，不在 UserDefaults 中存像素。
//

import Foundation

enum TriggerSpeechSnapshotStorage {
    private static let appFolder = "DesktopPet"
    private static let snapshotsFolder = "TriggerSnapshots"

    struct SnapshotStorageError: Error {}

    /// `…/Application Support/DesktopPet/TriggerSnapshots/`
    static func snapshotsDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let app = base.appendingPathComponent(appFolder, isDirectory: true)
        let dir = app.appendingPathComponent(snapshotsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 将 JPEG 写入 `\<recordId\>.jpg`，返回**文件名**（供 `TriggerSpeechRecord` 持久化）。
    @discardableResult
    static func saveJPEG(_ data: Data, recordId: UUID) throws -> String {
        guard !data.isEmpty else { throw SnapshotStorageError() }
        let dir = try snapshotsDirectoryURL()
        let name = "\(recordId.uuidString).jpg"
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return name
    }

    static func fileURL(storedFileName: String?) -> URL? {
        guard let name = storedFileName, !name.isEmpty else { return nil }
        guard let dir = try? snapshotsDirectoryURL() else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func deleteFile(storedFileName: String?) {
        guard let url = fileURL(storedFileName: storedFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
