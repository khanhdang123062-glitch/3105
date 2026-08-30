import Foundation
import UIKit

enum AppDisguiseError: LocalizedError {
    case bundleNotFound(String)
    case plistNotFound
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .bundleNotFound(let id):
            return "Không tìm thấy bundle của \(id). Exploit chưa active?"
        case .plistNotFound:
            return "Không tìm thấy Info.plist của app."
        case .writeFailed:
            return "Ghi Info.plist thất bại."
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

        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw AppDisguiseError.plistNotFound
        }

        plist["CFBundleDisplayName"] = displayName
        plist["CFBundleName"] = displayName

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        do {
            try data.write(to: plistURL)
        } catch {
            throw AppDisguiseError.writeFailed
        }

        // Ghi icon vào bundle
        let bundleDir = plistURL.deletingLastPathComponent()
        let iconSizes: [(String, Int)] = [
            ("AppIcon60x60@2x.png", 120),
            ("AppIcon60x60@3x.png", 180),
            ("AppIcon76x76@2x~ipad.png", 152),
        ]
        for (filename, size) in iconSizes {
            let iconURL = bundleDir.appendingPathComponent(filename)
            if let resized = resize(image: iconImage, to: CGSize(width: size, height: size)),
               let imgData = resized.pngData() {
                try? imgData.write(to: iconURL)
            }
        }

        // Lưu config
        let config = AppDisguiseConfig(displayName: displayName, iconName: iconName)
        if let configData = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(configData, forKey: configPrefix + bundleID)
        }

        notifySpringBoard()
    }

    static func reset(bundleID: String) throws {
        let plistURL = try findPlist(bundleID: bundleID)

        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw AppDisguiseError.plistNotFound
        }

        // Restore original name from bundle ID last component
        let originalName = plist["CFBundleName"] as? String ?? bundleID
        plist["CFBundleDisplayName"] = originalName

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        do {
            try data.write(to: plistURL)
        } catch {
            throw AppDisguiseError.writeFailed
        }

        UserDefaults.standard.removeObject(forKey: configPrefix + bundleID)
        notifySpringBoard()
    }

    private static func findPlist(bundleID: String) throws -> URL {
        let fm = FileManager.default
        let bundleRoot = URL(fileURLWithPath: "/var/containers/Bundle/Application")

        guard let uuids = try? fm.contentsOfDirectory(at: bundleRoot, includingPropertiesForKeys: nil) else {
            throw AppDisguiseError.bundleNotFound(bundleID)
        }

        for uuid in uuids {
            let apps = (try? fm.contentsOfDirectory(at: uuid, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                let plist = app.appendingPathComponent("Info.plist")
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
