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
    case destinationNotFound

    var errorDescription: String? {
        switch self {
        case .containerNotFound(let id):
            return "Không tìm thấy container của \(id). Hãy chắc chắn exploit đã active."
        case .extractionFailed:
            return "Giải nén file zip thất bại."
        case .noFilesPatched:
            return "Không có file nào được patch — kiểm tra lại cấu trúc zip."
        case .destinationNotFound:
            return "Không tìm thấy thư mục đích trong container game."
        }
    }
}

enum ZipPatchService {
    private static let backupRoot: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ZipPatchBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Tìm base path trong container — ưu tiên Documents, fallback về root
    private static func resolveBasePath(
        containerURL: URL,
        zipTopFolder: String
    ) -> URL {
        let fm = FileManager.default
        // Thử Documents/topFolder
        let docsFolder = containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(zipTopFolder)
        if fm.fileExists(atPath: docsFolder.path) {
            return containerURL.appendingPathComponent("Documents")
        }
        // Thử root/topFolder
        let rootFolder = containerURL.appendingPathComponent(zipTopFolder)
        if fm.fileExists(atPath: rootFolder.path) {
            return containerURL
        }
        // Default Documents
        return containerURL.appendingPathComponent("Documents")
    }

    // Lấy top-level folder trong zip (vd: "Resources")
    private static func topFolder(in extractedDir: URL) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: extractedDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        // Nếu có đúng 1 folder top-level thì đó là prefix
        let dirs = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        if dirs.count == 1 {
            return dirs[0].lastPathComponent
        }
        return nil
    }

    static func apply(zipURL: URL, bundleID: String) throws -> ZipPatchReceipt {
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            throw ZipPatchError.containerNotFound(bundleID)
        }

        let fm = FileManager.default
        let containerURL = URL(fileURLWithPath: containerPath)

        // Extract zip vào temp
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        guard (try? ZIPArchiveExtractor.extract(archiveURL: zipURL, into: tempDir)) != nil else {
            throw ZipPatchError.extractionFailed
        }

        // Detect top folder trong zip để tìm đúng base path
        let top = topFolder(in: tempDir) ?? ""
        let baseURL = resolveBasePath(containerURL: containerURL, zipTopFolder: top)

        // Tạo backup dir
        let backupDir = backupRoot
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Enumerate từng file trong zip
        let enumerator = fm.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var patchedFiles: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            // relativePath từ tempDir: vd "Resources/1.63.1/file.bytes"
            let relativePath = String(fileURL.path.dropFirst(tempDir.path.count + 1))
            let destinationURL = baseURL.appendingPathComponent(relativePath)
            let backupURL = backupDir.appendingPathComponent(relativePath)

            // Tạo thư mục đích nếu chưa có
            try? fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fm.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Backup file gốc nếu có
            if fm.fileExists(atPath: destinationURL.path) {
                try? fm.copyItem(at: destinationURL, to: backupURL)
                try? fm.removeItem(at: destinationURL)
            }

            // Copy file mới vào
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

        // Detect top folder từ backup để tìm đúng base
        let top = topFolder(in: receipt.backupDirectory) ?? ""
        let baseURL = resolveBasePath(containerURL: containerURL, zipTopFolder: top)

        for relativePath in receipt.patchedFiles {
            let destinationURL = baseURL.appendingPathComponent(relativePath)
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
        let bundleDir = backupRoot.appendingPathComponent(bundleID, isDirectory: true)
        guard let sessions = try? fm.contentsOfDirectory(
            at: bundleDir,
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
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            files.append(String(url.path.dropFirst(latestDir.path.count + 1)))
        }
        guard !files.isEmpty else { return nil }
        return ZipPatchReceipt(bundleID: bundleID, backupDirectory: latestDir, patchedFiles: files)
    }
}
