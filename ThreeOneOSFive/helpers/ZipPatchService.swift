import Foundation
import UIKit

struct ZipPatchReceipt {
    let bundleID: String
    let backupDirectory: URL
    let patchedFiles: [String]
}

enum ZipPatchError: LocalizedError {
    case containerNotFound(String)
    case extractionFailed
    case noFilesPatched

    var errorDescription: String? {
        switch self {
        case .containerNotFound(let id):
            return "Không tìm thấy container của \(id). Hãy chắc chắn exploit đã active."
        case .extractionFailed:
            return "Giải nén file zip thất bại."
        case .noFilesPatched:
            return "Không có file nào được patch — kiểm tra lại cấu trúc zip."
        }
    }
}

enum ZipPatchService {
    private static let backupRoot: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ZipPatchBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func apply(zipURL: URL, bundleID: String) throws -> ZipPatchReceipt {
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            throw ZipPatchError.containerNotFound(bundleID)
        }

        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        do {
            _ = try ZIPArchiveExtractor.extract(archiveURL: zipURL, into: tempDir)
        } catch {
            throw ZipPatchError.extractionFailed
        }

        let containerURL = URL(fileURLWithPath: containerPath)
        let backupDir = backupRoot
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let enumerator = fm.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var patchedFiles: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let relativePath = String(fileURL.path.dropFirst(tempDir.path.count + 1))
            let destinationURL = containerURL.appendingPathComponent(relativePath)
            let backupURL = backupDir.appendingPathComponent(relativePath)

            try? fm.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fm.fileExists(atPath: destinationURL.path) {
                try? fm.copyItem(at: destinationURL, to: backupURL)
                try? fm.removeItem(at: destinationURL)
            }

            try fm.copyItem(at: fileURL, to: destinationURL)
            patchedFiles.append(relativePath)
        }

        guard !patchedFiles.isEmpty else {
            throw ZipPatchError.noFilesPatched
        }

        return ZipPatchReceipt(
            bundleID: bundleID,
            backupDirectory: backupDir,
            patchedFiles: patchedFiles
        )
    }

    static func restore(receipt: ZipPatchReceipt) throws {
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: receipt.bundleID) else {
            throw ZipPatchError.containerNotFound(receipt.bundleID)
        }

        let fm = FileManager.default
        let containerURL = URL(fileURLWithPath: containerPath)

        for relativePath in receipt.patchedFiles {
            let destinationURL = containerURL.appendingPathComponent(relativePath)
            let backupURL = receipt.backupDirectory.appendingPathComponent(relativePath)

            try? fm.removeItem(at: destinationURL)

            if fm.fileExists(atPath: backupURL.path) {
                try? fm.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fm.copyItem(at: backupURL, to: destinationURL)
            }
        }

        try? fm.removeItem(at: receipt.backupDirectory)
    }

    static func latestReceipt(bundleID: String) -> ZipPatchReceipt? {
        let fm = FileManager.default
        let bundleBackupDir = backupRoot.appendingPathComponent(bundleID, isDirectory: true)
        guard let sessions = try? fm.contentsOfDirectory(
            at: bundleBackupDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let latest = sessions.max {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return d1 < d2
        }
        guard let latestDir = latest else { return nil }

        let enumerator = fm.enumerator(
            at: latestDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  v.isRegularFile == true else { continue }
            files.append(String(url.path.dropFirst(latestDir.path.count + 1)))
        }
        guard !files.isEmpty else { return nil }
        return ZipPatchReceipt(bundleID: bundleID, backupDirectory: latestDir, patchedFiles: files)
    }
}
