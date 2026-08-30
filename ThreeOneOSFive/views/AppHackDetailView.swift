import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum ActiveSheet: Identifiable {
    case importPatch
    case importZip
    case unlock

    var id: Int {
        switch self {
        case .importPatch: return 0
        case .importZip: return 1
        case .unlock: return 2
        }
    }
}

struct AppHackDetailView: View {
    let app: InstalledApp
    @ObservedObject var patchStore: PatchProjectStore

    @State private var enabledRules: Set<UUID> = []
    @State private var autoEnabled = true
    @State private var isPatching = false
    @State private var patchError: String?
    @State private var showSuccess = false
    @State private var activeSheet: ActiveSheet?
    @State private var importError: String?
    @State private var lastReceipts: [PatchTransactionReceipt] = []
    @State private var isRestoring = false
    @State private var showRestoreSuccess = false
    @State private var zipReceipt: ZipPatchReceipt?
    @State private var isZipPatching = false
    @State private var showVersionSpoof = false
    @State private var spoofVersion = ""
    @State private var isSpoofing = false
    @Environment(\.appLanguage) private var language

    private var appProjects: [PatchProject] {
        patchStore.items.compactMap(\.project).filter {
            $0.allBundleIdentifiers.contains(app.bundleID)
        }
    }

    private var allRules: [(project: PatchProject, rule: PatchRule)] {
        appProjects.flatMap { project in
            project.rules
                .filter { $0.bundleID == app.bundleID }
                .map { (project, $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                appHeader
                hackButton
                if !allRules.isEmpty { menuPatchSection }
                importPatchButton
                zipImportButton
                versionSpoofButton
                if !lastReceipts.isEmpty { restoreButton }
                if zipReceipt != nil { restoreZipButton }
                openAppButton
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initEnabledRules() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .importPatch:
                FileDocumentPicker(
                    allowedContentTypes: [UTType(filenameExtension: "3105") ?? .data, .data],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        activeSheet = nil
                        handleImport(result: result)
                    },
                    onCancel: { activeSheet = nil }
                )
                .ignoresSafeArea()
            case .importZip:
                FileDocumentPicker(
                    allowedContentTypes: [.data],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        activeSheet = nil
                        handleZipImport(result: result)
                    },
                    onCancel: { activeSheet = nil }
                )
                .ignoresSafeArea()
            case .unlock:
                AppPatchUnlockView(store: patchStore)
            }
        }
        .onChange(of: patchStore.passwordRequest?.id) { _ in
            if patchStore.passwordRequest != nil {
                activeSheet = .unlock
            }
        }
        .alert("Spoof Version", isPresented: $showVersionSpoof) {
            TextField("Nhập version mới (vd: 3.45.0)", text: $spoofVersion)
                .keyboardType(.numbersAndPunctuation)
            Button("Áp dụng") { applyVersionSpoof() }
            Button("Huỷ", role: .cancel) { spoofVersion = "" }
        } message: {
            Text("Nhập version muốn giả mạo. App Store sẽ nghĩ app đã được update.")
        }
        .alert(language.text("common.error"), isPresented: Binding(
            get: { patchError != nil },
            set: { if !$0 { patchError = nil } }
        )) {
            Button(language.text("common.ok"), role: .cancel) { patchError = nil }
        } message: {
            Text(patchError ?? "")
        }
        .alert("Import thất bại", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button(language.text("common.ok"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Đã mod thành công!", isPresented: $showSuccess) {
            Button(language.text("common.ok"), role: .cancel) {}
        }
        .alert("Đã xoá mod!", isPresented: $showRestoreSuccess) {
            Button(language.text("common.ok"), role: .cancel) {}
        }
        .alert(language.text("common.error"), isPresented: Binding(
            get: { patchStore.alert != nil },
            set: { if !$0 { patchStore.alert = nil } }
        )) {
            Button(language.text("common.ok"), role: .cancel) { patchStore.alert = nil }
        } message: {
            if let alert = patchStore.alert {
                Text(alert.message(language: language))
            }
        }
    }

    // MARK: - Header

    private var appHeader: some View {
        VStack(spacing: 10) {
            Group {
                if let icon = app.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(
                            Image(systemName: "app.dashed")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 90, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            Text(app.displayName).font(.title2.bold())
            Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Hack Button

    private var hackButton: some View {
        Button(action: applyHack) {
            HStack(spacing: 10) {
                if isPatching {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text("HACK").font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(allRules.isEmpty ? Color.secondary : AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isPatching || allRules.isEmpty)
    }

    // MARK: - Menu Patch

    private var menuPatchSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(AppTheme.accent)
                Text("MENU PATCH").font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $autoEnabled).labelsHidden().tint(AppTheme.accent)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))

            ForEach(Array(allRules.enumerated()), id: \.element.rule.id) { index, pair in
                let rule = pair.rule
                VStack(spacing: 0) {
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.15)).frame(width: 40, height: 40)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.replacementFilename.isEmpty ? rule.relativePath : rule.replacementFilename)
                                .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            let count = pair.project.rules.filter { $0.bundleID == app.bundleID }.count
                            Text("\(count) quy tắc thay thế").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { enabledRules.contains(rule.id) },
                            set: { on in
                                if on { enabledRules.insert(rule.id) }
                                else { enabledRules.remove(rule.id) }
                            }
                        )).labelsHidden().tint(AppTheme.accent)
                        Button { deleteProject(pair.project) } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(0.8))
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Buttons

    private var versionSpoofButton: some View {
        Button(action: { showVersionSpoof = true }) {
            HStack(spacing: 10) {
                if isSpoofing {
                    ProgressView().tint(AppTheme.accent)
                } else {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Spoof Version")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppTheme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isSpoofing)
    }

    private var importPatchButton: some View {
        Button(action: { activeSheet = .importPatch }) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill").font(.system(size: 15, weight: .semibold))
                Text("Import file .3105").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(AppTheme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1))
        }
    }

    private var zipImportButton: some View {
        Button(action: { activeSheet = .importZip }) {
            HStack(spacing: 10) {
                if isZipPatching {
                    ProgressView().tint(AppTheme.accent)
                } else {
                    Image(systemName: "doc.zipper").font(.system(size: 15, weight: .semibold))
                }
                Text("Import file .zip").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(AppTheme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 1))
        }
        .disabled(isZipPatching)
    }

    private var restoreButton: some View {
        Button(action: restoreFiles) {
            HStack(spacing: 10) {
                if isRestoring { ProgressView().tint(.orange) }
                else { Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 15, weight: .semibold)) }
                Text("Khôi phục file gốc (.3105)").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
        }
        .disabled(isRestoring)
    }

    private var restoreZipButton: some View {
        Button(action: restoreZip) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 15, weight: .semibold))
                Text("Khôi phục file gốc (.zip)").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
        }
    }

    private var openAppButton: some View {
        Button(action: openApp) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 14, weight: .semibold))
                Text("Mở ứng dụng").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Actions

    private func initEnabledRules() {
        let newIDs = Set(allRules.map(\.rule.id))
        enabledRules = enabledRules.union(newIDs)
        loadExistingReceipts()
        zipReceipt = ZipPatchService.latestReceipt(bundleID: app.bundleID)
    }

    private func loadExistingReceipts() {
        lastReceipts = appProjects.compactMap {
            DevicePatchService.latestReceipt(projectID: $0.id)
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            patchStore.importPackage(at: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.initEnabledRules()
            }
        }
    }

    private func handleZipImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            isZipPatching = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let receipt = try ZipPatchService.apply(zipURL: url, bundleID: app.bundleID)
                    DispatchQueue.main.async {
                        zipReceipt = receipt
                        isZipPatching = false
                        showSuccess = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        isZipPatching = false
                        patchError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func applyHack() {
        guard !isPatching else { return }
        isPatching = true
        patchError = nil
        let activeRules = enabledRules
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                for project in appProjects {
                    let filtered = PatchProject(
                        id: project.id, name: project.name,
                        bundleIdentifiers: project.bundleIdentifiers,
                        directories: project.directories,
                        rules: project.rules.filter { activeRules.contains($0.id) }
                    )
                    guard !filtered.rules.isEmpty else { continue }
                    _ = try DevicePatchService.apply(project: filtered)
                }
                DispatchQueue.main.async {
                    isPatching = false
                    showSuccess = true
                    loadExistingReceipts()
                }
            } catch {
                DispatchQueue.main.async {
                    isPatching = false
                    patchError = error.localizedDescription
                }
            }
        }
    }

    private func deleteProject(_ project: PatchProject) {
        guard let item = patchStore.items.first(where: { $0.id == project.id }) else { return }
        patchStore.delete(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { initEnabledRules() }
    }

    private func restoreFiles() {
        guard !isRestoring, !lastReceipts.isEmpty else { return }
        isRestoring = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                for receipt in lastReceipts {
                    try DevicePatchService.restore(receipt: receipt)
                }
                DispatchQueue.main.async {
                    isRestoring = false
                    showRestoreSuccess = true
                    lastReceipts = []
                }
            } catch {
                DispatchQueue.main.async {
                    isRestoring = false
                    patchError = error.localizedDescription
                }
            }
        }
    }

    private func restoreZip() {
        guard let receipt = zipReceipt else { return }
        isRestoring = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ZipPatchService.restore(receipt: receipt)
                DispatchQueue.main.async {
                    zipReceipt = nil
                    isRestoring = false
                    showRestoreSuccess = true
                }
            } catch {
                DispatchQueue.main.async {
                    isRestoring = false
                    patchError = error.localizedDescription
                }
            }
        }
    }

    private func applyVersionSpoof() {
        guard !spoofVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let version = spoofVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        spoofVersion = ""
        isSpoofing = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: app.bundleID) else {
                    throw NSError(domain: "Spoof", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Không tìm thấy container. Exploit chưa active?"
                    ])
                }

                // Tìm Info.plist trong bundle của game
                let containerURL = URL(fileURLWithPath: containerPath)
                let bundleURL = containerURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Bundle/Application")

                let fm = FileManager.default
                guard let bundles = try? fm.contentsOfDirectory(
                    at: bundleURL,
                    includingPropertiesForKeys: nil
                ) else {
                    throw NSError(domain: "Spoof", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Không tìm thấy bundle của game."
                    ])
                }

                var plistURL: URL?
                for bundle in bundles {
                    let apps = (try? fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)) ?? []
                    for appBundle in apps where appBundle.pathExtension == "app" {
                        let plist = appBundle.appendingPathComponent("Info.plist")
                        if fm.fileExists(atPath: plist.path) {
                            if let dict = NSDictionary(contentsOf: plist) as? [String: Any],
                               let bundleID = dict["CFBundleIdentifier"] as? String,
                               bundleID == app.bundleID {
                                plistURL = plist
                                break
                            }
                        }
                    }
                    if plistURL != nil { break }
                }

                guard let plistURL else {
                    throw NSError(domain: "Spoof", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Không tìm thấy Info.plist của game."
                    ])
                }

                guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
                    throw NSError(domain: "Spoof", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Không đọc được Info.plist."
                    ])
                }

                plist["CFBundleShortVersionString"] = version
                plist["CFBundleVersion"] = version

                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist,
                    format: .xml,
                    options: 0
                )
                try data.write(to: plistURL)

                DispatchQueue.main.async {
                    isSpoofing = false
                    showSuccess = true
                }
            } catch {
                DispatchQueue.main.async {
                    isSpoofing = false
                    patchError = error.localizedDescription
                }
            }
        }
    }

    private func openApp() {
        let workspaceSel = NSSelectorFromString("defaultWorkspace")
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              cls.responds(to: workspaceSel),
              let workspace = cls.perform(workspaceSel)?.takeUnretainedValue() as? NSObject else { return }
        let openSel = NSSelectorFromString("openApplicationWithBundleID:")
        if workspace.responds(to: openSel) {
            _ = workspace.perform(openSel, with: app.bundleID)
        }
    }
}

struct AppPatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                        .onChange(of: password) { _ in store.clearUnlockError() }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey)).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(language.text("patch.password_once_message"))
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}
