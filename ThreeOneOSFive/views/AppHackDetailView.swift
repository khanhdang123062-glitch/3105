import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PatchPickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

struct AppHackDetailView: View {
    let app: InstalledApp
    @ObservedObject var patchStore: PatchProjectStore

    @State private var enabledRules: Set<UUID> = []
    @State private var autoEnabled = true
    @State private var isPatching = false
    @State private var patchError: String?
    @State private var showSuccess = false
    @State private var showImporter = false
    @State private var lastReceipts: [PatchTransactionReceipt] = []
    @State private var isRestoring = false
    @State private var showRestoreSuccess = false
    @State private var showZipImporter = false
    @State private var zipReceipt: ZipPatchReceipt?
    @State private var isZipPatching = false
    @State private var importError: String?
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
                importButton
                zipImportButton
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
        .sheet(isPresented: $showImporter) {
            FileDocumentPicker(
                allowedContentTypes: PatchPickerPolicy.allowedContentTypes,
                copiesSelectedDocument: true,
                allowsMultipleSelection: false,
                onSelection: { result in
                    showImporter = false
                    handleImport(result: result)
                },
                onCancel: {
                    showImporter = false
                }
            )
            .ignoresSafeArea()
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
        .alert("Patch thành công!", isPresented: $showSuccess) {
            Button(language.text("common.ok"), role: .cancel) {}
        }
        .alert("Khôi phục thành công!", isPresented: $showRestoreSuccess) {
            Button(language.text("common.ok"), role: .cancel) {}
        }
        .sheet(item: $patchStore.passwordRequest, onDismiss: patchStore.cancelUnlock) { _ in
            AppPatchUnlockView(store: patchStore)
        }
        .alert(item: $patchStore.alert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

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

            Text(app.displayName)
                .font(.title2.bold())
            Text(app.bundleID)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var hackButton: some View {
        Button(action: applyHack) {
            HStack(spacing: 10) {
                if isPatching {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text("HACK")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(allRules.isEmpty ? Color.secondary : AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isPatching || allRules.isEmpty)
    }

    private var menuPatchSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("MENU PATCH")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $autoEnabled)
                    .labelsHidden()
                    .tint(AppTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))

            ForEach(Array(allRules.enumerated()), id: \.element.rule.id) { index, pair in
                let rule = pair.rule
                VStack(spacing: 0) {
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                rule.replacementFilename.isEmpty
                                    ? rule.relativePath
                                    : rule.replacementFilename
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            let count = pair.project.rules
                                .filter { $0.bundleID == app.bundleID }.count
                            Text("\(count) quy tắc thay thế")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { enabledRules.contains(rule.id) },
                            set: { on in
                                if on { enabledRules.insert(rule.id) }
                                else { enabledRules.remove(rule.id) }
                            }
                        ))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        Button {
                            deleteProject(pair.project)
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(0.8))
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var importButton: some View {
        Button(action: { showImporter = true }) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Import file .3105")
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
    }

    private var zipImportButton: some View {
        Button(action: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showZipImporter = true
            }
        }) {
            HStack(spacing: 10) {
                if isZipPatching {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Import file .zip")
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
        .disabled(isZipPatching)
    }

    private var restoreZipButton: some View {
        Button(action: restoreZip) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Khôi phục file gốc (Zip)")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var restoreButton: some View {
        Button(action: restoreFiles) {
            HStack(spacing: 10) {
                if isRestoring {
                    ProgressView().tint(.orange)
                } else {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Khôi phục file gốc")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(isRestoring)
    }

    private var openAppButton: some View {
        Button(action: openApp) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Mở ứng dụng")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func initEnabledRules() {
        let newIDs = Set(allRules.map(\.rule.id))
        enabledRules = enabledRules.union(newIDs)
        loadExistingReceipts()
    }

    private func loadExistingReceipts() {
        let receipts = appProjects.compactMap {
            DevicePatchService.latestReceipt(projectID: $0.id)
        }
        lastReceipts = receipts
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
                initEnabledRules()
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
                        id: project.id,
                        name: project.name,
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            initEnabledRules()
        }
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

    private func handleZipImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            patchError = error.localizedDescription
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
                        .onChange(of: password) { _ in
                            store.clearUnlockError()
                        }
                    if let errorKey = store.unlockErrorKey {
                        Text(language.text(errorKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
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
