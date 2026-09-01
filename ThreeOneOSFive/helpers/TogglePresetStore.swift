import Foundation

struct TogglePreset: Codable, Identifiable {
    let id: Int
    var name: String
    var fileName: String
    var fileType: String // "3105" or "zip"
    var filePath: String
    var isEnabled: Bool = true
}

enum TogglePresetStore {
    private static let storageKey = "toggle.presets."

    static func presets(for bundleID: String) -> [TogglePreset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey + bundleID),
              let presets = try? JSONDecoder().decode([TogglePreset].self, from: data)
        else { return [] }
        return presets
    }

    static func save(_ presets: [TogglePreset], for bundleID: String) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: storageKey + bundleID)
        }
    }

    static func add(preset: TogglePreset, for bundleID: String) {
        var all = presets(for: bundleID)
        all.removeAll { $0.id == preset.id }
        all.append(preset)
        all.sort { $0.id < $1.id }
        save(all, for: bundleID)
    }

    static func remove(id: Int, for bundleID: String) {
        var all = presets(for: bundleID)
        all.removeAll { $0.id == id }
        // Xoá file cache
        if let preset = all.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(atPath: preset.filePath)
        }
        save(all, for: bundleID)
    }

    static func nextID(for bundleID: String) -> Int {
        let all = presets(for: bundleID)
        return (all.map(\.id).max() ?? 0) + 1
    }

    // Lưu file vào Application Support
    static func cacheFile(sourceURL: URL, bundleID: String, toggleID: Int, fileType: String) throws -> String {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("TogglePresets/\(bundleID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("toggle_\(toggleID).\(fileType)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest.path
    }
}
