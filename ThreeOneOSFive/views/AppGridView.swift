import SwiftUI
import UIKit

private struct HardcodedApp {
    let bundleID: String
    let displayName: String
}

private let targetApps: [HardcodedApp] = [
    HardcodedApp(bundleID: "com.garena.game.kgvn", displayName: "Liên Quân Mobile"),
    HardcodedApp(bundleID: "com.dts.freefireth", displayName: "Free Fire"),
    HardcodedApp(bundleID: "dazz.camera.vintagecamera", displayName: "Dazzcam"),
    HardcodedApp(bundleID: "com.lemon.lvoverseas", displayName: "Capcut"),
    HardcodedApp(bundleID: "vn.vng.pubgmobile", displayName: "PUBG"),
    HardcodedApp(bundleID: "com.dts.freefiremax", displayName: "Free Fire Max"),
]

struct AppGridView: View {
    @StateObject private var patchStore = PatchProjectStore()
    @State private var appEntries: [(app: InstalledApp?, info: HardcodedApp)] = []
    @State private var isLoading = true

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
