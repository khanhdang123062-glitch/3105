import Foundation
import UIKit

enum AppDisguiseError: LocalizedError {
    case bundlePathNotFound
    case infoPlistNotFound
    case writeFailed
    case iconWriteFailed

    var errorDescription: String? {
        switch self {
        case .bundlePathNotFound: return "Không tìm thấy bundle path của app."
        case .infoPlistNotFound: return "Không tìm thấy Info.plist."
        case .writeFailed: return "Ghi Info.plist thất bại. Exploit chưa active?"
        case .iconWriteFailed: return "Ghi icon thất bại."
        }
    }
}

struct AppDisguiseConfig: Codable {
    var displayName: String
    var iconName: String // tên icon preset
}

enum AppDisguiseService {
    private static let configKey = "app.disguise.config"

    static var currentConfig: AppDisguiseConfig? {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AppDisguiseConfig.self, from: data)
        else { return nil }
        return config
    }

    static func apply(displayName: String, iconName: String, iconImage: UIImage) throws {
        let bundlePath = Bundle.main.bundlePath
        let plistPath = (bundlePath as NSString).appendingPathComponent("Info.plist")

        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw AppDisguiseError.infoPlistNotFound
        }

        guard var plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            throw AppDisguiseError.infoPlistNotFound
        }

        // Đổi display name
        plist["CFBundleDisplayName"] = displayName
        plist["CFBundleName"] = displayName

        // Ghi lại Info.plist
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        do {
            try plistData.write(to: URL(fileURLWithPath: plistPath))
        } catch {
            throw AppDisguiseError.writeFailed
        }

        // Ghi icon mới vào bundle
        if let iconData = iconImage.pngData() {
            let iconSizes = [
                ("AppIcon60x60@2x.png", 120),
                ("AppIcon60x60@3x.png", 180),
                ("AppIcon76x76@2x~ipad.png", 152),
            ]
            for (filename, size) in iconSizes {
                let iconPath = (bundlePath as NSString).appendingPathComponent(filename)
                let resized = resize(image: iconImage, to: CGSize(width: size, height: size))
                if let data = resized?.pngData() {
                    try? data.write(to: URL(fileURLWithPath: iconPath))
                }
            }
        }

        // Lưu config
        let config = AppDisguiseConfig(displayName: displayName, iconName: iconName)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }

        // Notify SpringBoard refresh
        notifySpringBoard()
    }

    static func reset() throws {
        let bundlePath = Bundle.main.bundlePath
        let plistPath = (bundlePath as NSString).appendingPathComponent("Info.plist")

        guard var plist = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            throw AppDisguiseError.infoPlistNotFound
        }

        plist["CFBundleDisplayName"] = "3105"
        plist["CFBundleName"] = "3105"

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        do {
            try plistData.write(to: URL(fileURLWithPath: plistPath))
        } catch {
            throw AppDisguiseError.writeFailed
        }

        UserDefaults.standard.removeObject(forKey: configKey)
        notifySpringBoard()
    }

    private static func notifySpringBoard() {
        // Notify SpringBoard to refresh app icon cache
        let notifyNames = [
            "com.apple.mobile.application_installed",
            "SBApplicationCacheChanged",
        ]
        for name in notifyNames {
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
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
}
