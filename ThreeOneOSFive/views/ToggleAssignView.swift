import SwiftUI
import UniformTypeIdentifiers

struct ToggleAssignView: View {
    let app: InstalledApp
    @ObservedObject var patchStore: PatchProjectStore

    @Environment(\.dismiss) private var dismiss
    @State private var presets: [TogglePreset] = []
    @State private var showFilePicker = false
    @State private var selectedToggleID: Int?
    @State private var toggleName = ""
    @State private var showAddToggle = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(presets) { preset in
                    HStack(spacing: 12) {
                        Text("\(preset.id)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 4) {
                                Text(preset.fileType.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(preset.fileName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            selectedToggleID = preset.id
                            showFilePicker = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deletePreset(id: preset.id)
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Danh sách toggle")
            } footer: {
                Text("Vuốt trái để xoá. Bấm icon để đổi file.")
            }

            Section {
                Button(action: { showAddToggle = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text("Thêm toggle mới")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
        .navigationTitle("Nhập file vào toggle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Xong") { dismiss() }
            }
        }
        .onAppear { presets = TogglePresetStore.presets(for: app.bundleID) }
        .alert("Thêm toggle", isPresented: $showAddToggle) {
            TextField("Tên toggle (vd: Mod Skin)", text: $toggleName)
            Button("Chọn file") {
                let newID = TogglePresetStore.nextID(for: app.bundleID)
                selectedToggleID = newID
                showFilePicker = true
            }
            Button("Huỷ", role: .cancel) { toggleName = "" }
        } message: {
            Text("Nhập tên rồi chọn file .3105 hoặc .zip")
        }
        .alert("Lỗi", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showFilePicker) {
            FileDocumentPicker(
                allowedContentTypes: [UTType(filenameExtension: "3105") ?? .data, .data],
                copiesSelectedDocument: true,
                allowsMultipleSelection: false,
                onSelection: { result in
                    showFilePicker = false
                    handleFileSelected(result: result)
                },
                onCancel: {
                    showFilePicker = false
                    toggleName = ""
                    selectedToggleID = nil
                }
            )
            .ignoresSafeArea()
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Đang lưu file...").foregroundStyle(.white).font(.subheadline)
                    }
                    .padding(24)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func handleFileSelected(result: Result<[URL], Error>) {
        guard let toggleID = selectedToggleID else { return }
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            toggleName = ""
            selectedToggleID = nil
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            isImporting = true
            let name = toggleName.isEmpty
                ? (presets.first(where: { $0.id == toggleID })?.name ?? "Toggle \(toggleID)")
                : toggleName
            let fileExt = url.pathExtension.lowercased() == "zip" ? "zip" : "3105"
            let fileName = url.lastPathComponent

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let cachedPath = try TogglePresetStore.cacheFile(
                        sourceURL: url,
                        bundleID: app.bundleID,
                        toggleID: toggleID,
                        fileType: fileExt
                    )
                    let preset = TogglePreset(
                        id: toggleID,
                        name: name,
                        fileName: fileName,
                        fileType: fileExt,
                        filePath: cachedPath
                    )
                    TogglePresetStore.add(preset: preset, for: app.bundleID)
                    DispatchQueue.main.async {
                        isImporting = false
                        toggleName = ""
                        selectedToggleID = nil
                        presets = TogglePresetStore.presets(for: app.bundleID)
                    }
                } catch {
                    DispatchQueue.main.async {
                        isImporting = false
                        toggleName = ""
                        selectedToggleID = nil
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func deletePreset(id: Int) {
        TogglePresetStore.remove(id: id, for: app.bundleID)
        presets = TogglePresetStore.presets(for: app.bundleID)
    }
}
