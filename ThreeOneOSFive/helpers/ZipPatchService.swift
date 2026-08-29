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
    case resourcesFolderNotFound

    var errorDescription: String? {
        switch self {
        case .containerNotFound(let id):
            return "Không tìm thấy container của \(id). Hãy chắc chắn exploit đã active."
        case .extractionFailed:
            return "Giải nén file zip thất bại."
        case .noFilesPatched:
            return "Không có file nào được patch."
        case .resourcesFolderNotFound:
            return "Không tìm thấy folder Resources trong zip hoặc trong game."
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

    // Tìm folder "Resources" bên trong thư mục đã extract (bất kể nằm ở cấp nào)
    private static func findResourcesFolder(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        while let url = enumerator.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  url.lastPathComponent.lowercased() == "resources" else { continue }
            return url
        }
        return nil
    }

    // Tìm folder "Resources" trong game container
    private static func findGameResourcesFolder(containerPath: String) -> URL? {
        let fm = FileManager.default
        let containerURL = URL(fileURLWithPath: containerPath)

        // Thử Documents/Resources trước
        let docsResources = containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent("Resources")
        if fm.fileExists(atPath: docsResources.path) {
            return docsResources
        }

        // Thử root/Resources
        let rootResources = containerURL.appendingPathComponent("Resources")
        if fm.fileExists(atPath: rootResources.path) {
            return rootResources
        }

        // Fallback: tạo Documents/Resources
        return containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent("Resources")
    }

    static func apply(zipURL: URL, bundleID: String) throws -> ZipPatchReceipt {
        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
            throw ZipPatchError.containerNotFound(bundleID)
        }

        let fm = FileManager.default

        // Extract zip
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        guard (try? ZIPArchiveExtractor.extract(archiveURL: zipURL, into: tempDir)) != nil else {
            throw ZipPatchError.extractionFailed
        }

        // Tìm folder Resources trong zip đã extract
        guard let zipResourcesURL = findResourcesFolder(in: tempDir) else {
            throw ZipPatchError.resourcesFolderNotFound
        }

        // Tìm folder Resources trong game
        let gameResourcesURL = findGameResourcesFolder(containerPath: containerPath)!

        // Backup dir
        let backupDir = backupRoot
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Enumerate từng file trong Resources của zip
        let enumerator = fm.enumerator(
            at: zipResourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var patchedFiles: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }

            // relativePath tính từ Resources/ trong zip
            let relativePath = String(fileURL.path.dropFirst(zipResourcesURL.path.count + 1))

            // Đích: game's Resources/relativePath
            let destinationURL = gameResourcesURL.appendingPathComponent(relativePath)

            // Backup
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

            // Copy file mới
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

        let gameResourcesURL = findGameResourcesFolder(containerPath: containerPath)!
        let fm = FileManager.default

        for relativePath in receipt.patchedFiles {
            let destinationURL = gameResourcesURL.appendingPathComponent(relativePath)
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
