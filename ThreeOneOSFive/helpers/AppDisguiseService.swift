import Foundation
import UIKit

enum AppDisguiseError: LocalizedError {
    case bundleNotFound(String)
    case plistNotFound
    case writeFailed(String)
    case notWritable

    var errorDescription: String? {
        switch self {
        case .bundleNotFound(let id):
            return "Không tìm thấy bundle của \(id). Exploit chưa active?"
        case .plistNotFound:
            return "Không tìm thấy Info.plist."
        case .writeFailed(let reason):
            return "Ghi thất bại: \(reason). App bundle read-only — exploit cần active."
        case .notWritable:
            return "App bundle không có quyền ghi. Hãy chắc chắn exploit đã chạy thành công."
        }
    }
}

struct AppDisguiseConfig: Codable {
    var displayName: String
    var iconName: String
}

enum AppDisguiseService {
    private static let configPrefix = "app.disguise."

    static func currentConfig(bundleID: String) -> AppDisguiseConfig? {
        guard let data = UserDefaults.standard.data(forKey: configPrefix + bundleID),
              let config = try? JSONDecoder().decode(AppDisguiseConfig.self, from: data)
        else { return nil }
        return config
    }

    static func apply(bundleID: String, displayName: String, iconName: String, iconImage: UIImage) throws {
        let plistURL = try findPlist(bundleID: bundleID)

        // Check write access trước
        guard hasReadWriteAccess(to: plistURL.path) else {
            throw AppDisguiseError.notWritable
        }

        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw AppDisguiseError.plistNotFound
        }

        // Lưu original name nếu chưa có
        if currentConfig(bundleID: bundleID) == nil {
            let originalName = plist["CFBundleDisplayName"] as? String
                ?? plist["CFBundleName"] as? String
                ?? bundleID
            UserDefaults.standard.set(originalName, forKey: configPrefix + bundleID + ".original")
        }

        plist["CFBundleDisplayName"] = displayName
        plist["CFBundleName"] = displayName

        // Ghi bằng low-level để bypass FileManager restrictions
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try writeData(plistData, to: plistURL.path)

        // Ghi icon
        let bundleDir = plistURL.deletingLastPathComponent()
        let iconSizes: [(String, Int)] = [
            ("AppIcon60x60@2x.png", 120),
            ("AppIcon60x60@3x.png", 180),
            ("AppIcon76x76@2x~ipad.png", 152),
        ]
        for (filename, size) in iconSizes {
            let iconPath = bundleDir.appendingPathComponent(filename).path
            if let resized = resize(image: iconImage, to: CGSize(width: size, height: size)),
               let imgData = resized.pngData() {
                try? writeData(imgData, to: iconPath)
            }
        }

        let config = AppDisguiseConfig(displayName: displayName, iconName: iconName)
        if let configData = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(configData, forKey: configPrefix + bundleID)
        }

        notifySpringBoard()
    }

    static func reset(bundleID: String) throws {
        let plistURL = try findPlist(bundleID: bundleID)

        guard hasReadWriteAccess(to: plistURL.path) else {
            throw AppDisguiseError.notWritable
        }

        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw AppDisguiseError.plistNotFound
        }

        let originalName = UserDefaults.standard.string(forKey: configPrefix + bundleID + ".original")
            ?? (plist["CFBundleName"] as? String)
            ?? bundleID

        plist["CFBundleDisplayName"] = originalName
        plist["CFBundleName"] = originalName

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try writeData(data, to: plistURL.path)

        UserDefaults.standard.removeObject(forKey: configPrefix + bundleID)
        UserDefaults.standard.removeObject(forKey: configPrefix + bundleID + ".original")

        notifySpringBoard()
    }

    // Low-level write dùng C file descriptor
    private static func writeData(_ data: Data, to path: String) throws {
        let fd = open(path, O_WRONLY | O_TRUNC | O_CLOEXEC)
        guard fd >= 0 else {
            throw AppDisguiseError.writeFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        let result = data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress, data.count)
        }
        if result < 0 {
            throw AppDisguiseError.writeFailed(String(cString: strerror(errno)))
        }
    }

    private static func hasReadWriteAccess(to path: String) -> Bool {
        let fd = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    private static func findPlist(bundleID: String) throws -> URL {
        let fm = FileManager.default

        // Dùng bundle của 3105 để tìm đúng root path (tương thích mọi iOS)
        let myBundlePath = URL(fileURLWithPath: Bundle.main.bundlePath)
        let bundleRoot = myBundlePath
            .deletingLastPathComponent() // bỏ 3105.app
            .deletingLastPathComponent() // bỏ UUID → ra /var/containers/Bundle/Application

        guard let uuids = try? fm.contentsOfDirectory(
            at: bundleRoot,
            includingPropertiesForKeys: nil
        ) else {
            throw AppDisguiseError.bundleNotFound(bundleID)
        }

        for uuid in uuids {
            guard let apps = try? fm.contentsOfDirectory(at: uuid, includingPropertiesForKeys: nil) else { continue }
            for app in apps where app.pathExtension == "app" {
                let plist = app.appendingPathComponent("Info.plist")
                guard fm.fileExists(atPath: plist.path) else { continue }
                if let dict = NSDictionary(contentsOf: plist) as? [String: Any],
                   let id = dict["CFBundleIdentifier"] as? String,
                   id == bundleID {
                    return plist
                }
            }
        }
        throw AppDisguiseError.bundleNotFound(bundleID)
    }

    private static func notifySpringBoard() {
        for name in ["com.apple.mobile.application_installed", "SBApplicationCacheChanged"] {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(name as CFString),
                nil, nil, true
            )
        }
    }

    private static func resize(image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}
