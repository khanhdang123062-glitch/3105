import SwiftUI
import UIKit
import PhotosUI

private struct HardcodedApp {
    let bundleID: String
    let displayName: String
}

private let targetApps: [HardcodedApp] = [
    HardcodedApp(bundleID: "com.garena.game.kgvn", displayName: "Liên Quân Mobile"),
    HardcodedApp(bundleID: "com.dts.freefireth", displayName: "Free Fire"),
    HardcodedApp(bundleID: "vn.vng.pubgmobile", displayName: "PUBG"),
    HardcodedApp(bundleID: "com.lemon.lvoverseas", displayName: "Capcut"),
    HardcodedApp(bundleID: "Dazz.camera.vintagecamera", displayName: "Dazz cam"),
]

struct AppGridView: View {
    @StateObject private var patchStore = PatchProjectStore()
    @State private var appEntries: [(app: InstalledApp?, info: HardcodedApp)] = []
    @State private var isLoading = true
    @State private var backgroundImage: UIImage? = BackgroundStore.load()
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                // Background image
                if let bg = backgroundImage {
                    Image(uiImage: bg)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(0.3))
                }
                Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(appEntries, id: \.info.bundleID) { entry in
                                NavigationLink(
                                    destination: AppHackDetailView(
                                        app: entry.app ?? makeFallback(entry.info),
                                        patchStore: patchStore
                                    )
                                ) {
                                    AppGridCell(
                                        name: entry.info.displayName,
                                        bundleID: entry.info.bundleID,
                                        icon: entry.app?.icon
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("Ứng dụng")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadApps() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
            }
            .onChange(of: photoPickerItem) { item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        backgroundImage = img
                        BackgroundStore.save(data: data)
                    }
                }
            }
            } // end ZStack
        }
    }

    private func loadApps() {
        isLoading = true
        patchStore.reload()
        DispatchQueue.global(qos: .userInitiated).async {
            let bundleMetadata = ContainerStore.applicationBundleMetadataCatalog()
            let apiApps = ContainerStore.applyingBundleMetadata(
                to: ContainerStore.installedAppsFromAPI(),
                catalog: bundleMetadata
            )
            let mcmApps = ContainerStore.installedAppsFromMCM(
                identifiers: ContainerStore.dynamicAppIdentifiers(),
                bundleMetadata: bundleMetadata
            )
            let allApps = apiApps + mcmApps
            let entries: [(app: InstalledApp?, info: HardcodedApp)] = targetApps.map { info in
                let found = allApps.first { $0.bundleID == info.bundleID }
                return (app: found, info: info)
            }
            DispatchQueue.main.async {
                appEntries = entries
                isLoading = false
            }
        }
    }

    private func makeFallback(_ info: HardcodedApp) -> InstalledApp {
        InstalledApp(
            bundleID: info.bundleID,
            name: info.displayName,
            containerPath: "",
            version: "",
            icon: nil
        )
    }
}

private struct AppGridCell: View {
    let name: String
    let bundleID: String
    let icon: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let icon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

            VStack(spacing: 2) {
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum BackgroundStore {
    private static let key = "appgrid.background"
    private static let fileURL: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("appgrid_bg.jpg")
    }()

    static func save(data: Data) {
        try? data.write(to: fileURL)
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
}
