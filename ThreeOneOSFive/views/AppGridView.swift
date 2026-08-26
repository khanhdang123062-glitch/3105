import SwiftUI
import UIKit

struct AppGridView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var patchStore = PatchProjectStore()
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = false
    @State private var searchText = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var filteredApps: [InstalledApp] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSearchField(
                    text: $searchText,
                    prompt: language.text("browser.search"),
                    clearLabel: language.text("common.clear")
                )
                Divider()
                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if apps.isEmpty {
                        Text(language.text("browser.empty"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredApps.isEmpty {
                        Text(language.text("browser.no_results"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(filteredApps) { app in
                                    NavigationLink(
                                        destination: AppHackDetailView(app: app, patchStore: patchStore)
                                    ) {
                                        AppGridCell(app: app)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .navigationTitle(language.text("tab.apps"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { loadApps() } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
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
            let dynamicIdentifiers = ContainerStore.dynamicAppIdentifiers()
            let mcmApps = ContainerStore.installedAppsFromMCM(
                identifiers: dynamicIdentifiers,
                bundleMetadata: bundleMetadata
            )
            let merged = mergeApps(api: apiApps, mcm: mcmApps)
            let sorted = merged.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            DispatchQueue.main.async {
                apps = sorted
                isLoading = false
            }
        }
    }

    private func mergeApps(api: [InstalledApp], mcm: [InstalledApp]) -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for app in api + mcm {
            if seen.insert(app.bundleID).inserted {
                result.append(app)
            }
        }
        return result
    }
}

private struct AppGridCell: View {
    let app: InstalledApp

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(
                            Image(systemName: "app.dashed")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

            VStack(spacing: 2) {
                Text(app.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(app.bundleID)
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
