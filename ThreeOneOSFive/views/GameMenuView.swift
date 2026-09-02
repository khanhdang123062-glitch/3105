import SwiftUI
import UIKit

struct GameMenuView: View {
    let app: InstalledApp
    @ObservedObject var patchStore: PatchProjectStore

    @State private var presets: [TogglePreset] = []
    @State private var isPatching = false
    @State private var patchError: String?
    @State private var showSuccess = false
    @State private var showAssign = false
    @State private var renamingID: Int?
    @State private var renameText = ""
    @State private var fovValue: Double = {
        let v = UserDefaults.standard.double(forKey: "fov.value")
        return v == 0 ? 50 : v
    }()
    @State private var offsetNoRecoil = UserDefaults.standard.string(forKey: "offset.norecoil") ?? ""
    @State private var offsetGhost = UserDefaults.standard.string(forKey: "offset.ghost") ?? ""
    @State private var offsetSpeed = UserDefaults.standard.string(forKey: "offset.speed") ?? ""
    @State private var editingOffset: String? = nil
    @State private var offsetInput = ""
    @State private var noRecoilEnabled = false
    @State private var ghostEnabled = false
    @State private var speedEnabled = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                ScrollView {
                    VStack(spacing: 16) {
                        patchSection
                        if !presets.isEmpty {
                            otherSection
                        }
                    }
                    .padding(16)
                }
                bottomButtons
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPresets() }
        .alert("Đã mod thành công!", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        }
        .alert("Đổi tên toggle", isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField("Tên mới", text: $renameText)
            Button("Lưu") {
                if let id = renamingID, !renameText.isEmpty {
                    if let idx = presets.firstIndex(where: { $0.id == id }) {
                        presets[idx].name = renameText
                        TogglePresetStore.save(presets, for: app.bundleID)
                    }
                }
                renamingID = nil
                renameText = ""
            }
            Button("Huỷ", role: .cancel) {
                renamingID = nil
                renameText = ""
            }
        } message: {
            Text("Nhập tên mới cho toggle \(renamingID ?? 0)")
        }
        .alert("Lỗi", isPresented: Binding(
            get: { patchError != nil },
            set: { if !$0 { patchError = nil } }
        )) {
            Button("OK", role: .cancel) { patchError = nil }
        } message: {
            Text(patchError ?? "")
        }
        .sheet(isPresented: $showAssign, onDismiss: loadPresets) {
            NavigationStack {
                ToggleAssignView(app: app, patchStore: patchStore)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("MENU")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .kerning(4)
            Text(app.displayName.uppercased())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.04))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.white.opacity(0.1)), alignment: .bottom)
    }

    // MARK: - Patch Section

    private let totalToggles = 5

    private var patchSection: some View {
        VStack(spacing: 0) {
            sectionHeader("PATCH")
            VStack(spacing: 0) {
                ForEach(1...totalToggles, id: \.self) { id in
                    let preset = presets.first { $0.id == id }
                    let hasFile = preset != nil
                    let isLast = id == totalToggles

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("\(id)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(hasFile ? AppTheme.accent : .white.opacity(0.2))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(preset?.name ?? defaultToggleName(id))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(hasFile ? .white : .white.opacity(0.3))
                                    Button {
                                        renameText = preset?.name ?? defaultToggleName(id)
                                        renamingID = id
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                }
                                if let preset {
                                    Text(preset.fileType.uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent.opacity(0.7))
                                        .kerning(1)
                                } else {
                                    Text("Chưa có file")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.2))
                                }
                            }

                            Spacer()

                            if hasFile, let idx = presets.firstIndex(where: { $0.id == id }) {
                                Toggle("", isOn: Binding(
                                    get: { presets[idx].isEnabled },
                                    set: { val in
                                        presets[idx].isEnabled = val
                                        TogglePresetStore.save(presets, for: app.bundleID)
                                    }
                                ))
                                .labelsHidden()
                                .tint(AppTheme.accent)
                            } else {
                                Toggle("", isOn: .constant(false))
                                    .labelsHidden()
                                    .disabled(true)
                                    .opacity(0.3)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if !isLast {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 50)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Other Section

    private var fovSection: some View {
        VStack(spacing: 0) {
            sectionHeader("FOV")
            VStack(spacing: 12) {
                HStack {
                    Text("Field of View")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(fovValue))")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 36)
                }

                Slider(value: $fovValue, in: 1...100, step: 1) {
                    Text("FOV")
                } minimumValueLabel: {
                    Text("1")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                } maximumValueLabel: {
                    Text("100")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .tint(AppTheme.accent)
                .onChange(of: fovValue) { val in
                    UserDefaults.standard.set(val, forKey: "fov.value")
                }

                HStack {
                    ForEach([25, 50, 75, 100], id: \.self) { val in
                        Button {
                            fovValue = Double(val)
                        } label: {
                            Text("\(val)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Int(fovValue) == val ? .black : AppTheme.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(Int(fovValue) == val ? AppTheme.accent : AppTheme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var otherSection: some View {
        VStack(spacing: 0) {
            sectionHeader("OTHER")
            VStack(spacing: 0) {
                offsetRow(index: "A", title: "No Recoil", key: "offset.norecoil",
                         value: $offsetNoRecoil, isOn: $noRecoilEnabled,
                         onToggle: { on in applyOtherPatch(offset: offsetNoRecoil, enable: on) })
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 50)
                offsetRow(index: "B", title: "Ghost Mode", key: "offset.ghost",
                         value: $offsetGhost, isOn: $ghostEnabled,
                         onToggle: { on in applyOtherPatch(offset: offsetGhost, enable: on) })
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 50)
                offsetRow(index: "C", title: "Speed Hack", key: "offset.speed",
                         value: $offsetSpeed, isOn: $speedEnabled,
                         onToggle: { on in applyOtherPatch(offset: offsetSpeed, enable: on) })
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .alert("Nhập offset", isPresented: Binding(
            get: { editingOffset != nil },
            set: { if !$0 { editingOffset = nil } }
        )) {
            TextField("0x00000000", text: $offsetInput)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
            Button("Lưu") {
                if let key = editingOffset {
                    UserDefaults.standard.set(offsetInput, forKey: key)
                    switch key {
                    case "offset.norecoil": offsetNoRecoil = offsetInput
                    case "offset.ghost": offsetGhost = offsetInput
                    case "offset.speed": offsetSpeed = offsetInput
                    default: break
                    }
                }
                editingOffset = nil
                offsetInput = ""
            }
            Button("Huỷ", role: .cancel) {
                editingOffset = nil
                offsetInput = ""
            }
        } message: {
            Text("Nhập hex offset cho chức năng này.")
        }
    }

    private func offsetRow(index: String, title: String, key: String,
                            value: Binding<String>, isOn: Binding<Bool>,
                            onToggle: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(index)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(value.wrappedValue.isEmpty ? .white.opacity(0.2) : AppTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(value.wrappedValue.isEmpty ? .white.opacity(0.3) : .white)
                Text(value.wrappedValue.isEmpty ? "Chưa có offset" : value.wrappedValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(value.wrappedValue.isEmpty ? .white.opacity(0.2) : AppTheme.accent.opacity(0.8))
            }
            Spacer()
            Button {
                offsetInput = value.wrappedValue
                editingOffset = key
            } label: {
                Text(value.wrappedValue.isEmpty ? "Nhập" : "Sửa")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(value.wrappedValue.isEmpty ? Color.white.opacity(0.2) : AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { val in
                    isOn.wrappedValue = val
                    onToggle(val)
                }
            ))
            .labelsHidden()
            .tint(AppTheme.accent)
            .disabled(value.wrappedValue.isEmpty)
            .opacity(value.wrappedValue.isEmpty ? 0.3 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func applyOtherPatch(offset: String, enable: Bool) {
        guard !offset.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try GameMemoryService.applyBoolPatch(
                    offset: offset,
                    value: enable,
                    bundleID: app.bundleID
                )
            } catch {
                DispatchQueue.main.async {
                    patchError = error.localizedDescription
                }
            }
        }
    }


    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.2))
            Text("Chưa có toggle nào\nBấm \"Nhập file\" để thêm")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .kerning(3)
            Spacer()
        }
        .padding(.bottom, 8)
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Nhập file
                Button(action: { showAssign = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Nhập file")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.accent.opacity(0.4), lineWidth: 1)
                    )
                }

                // HACK
                Button(action: applyHack) {
                    HStack(spacing: 6) {
                        if isPatching {
                            ProgressView().tint(.black).controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text("HACK")
                            .font(.system(size: 14, weight: .bold))
                            .kerning(2)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(presets.filter(\.isEnabled).isEmpty ? Color.secondary : AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isPatching || presets.filter(\.isEnabled).isEmpty)
            }

            // START
            Button(action: openApp) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("START")
                        .font(.system(size: 17, weight: .bold))
                        .kerning(3)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.4), radius: 8, x: 0, y: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .padding(.top, 8)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Actions

    // *** ĐỔI TÊN MẶC ĐỊNH TOGGLE Ở ĐÂY ***
    private func defaultToggleName(_ id: Int) -> String {
        switch id {
        case 1: return "Mod Skin"
        case 2: return "Hack Map"
        case 3: return "Cam Xa"
        case 4: return "Toggle 4"
        case 5: return "Toggle 5"
        default: return "Toggle \(id)"
        }
    }

    private func loadPresets() {
        presets = TogglePresetStore.presets(for: app.bundleID)
    }

    private func applyHack() {
        guard !isPatching else { return }
        let active = presets.filter(\.isEnabled)
        guard !active.isEmpty else { return }
        isPatching = true

        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []

            for preset in active {
                let fileURL = URL(fileURLWithPath: preset.filePath)
                guard FileManager.default.fileExists(atPath: preset.filePath) else {
                    errors.append("Toggle \(preset.id): file không tồn tại")
                    continue
                }

                if preset.fileType == "zip" {
                    do {
                        _ = try ZipPatchService.apply(zipURL: fileURL, bundleID: app.bundleID)
                    } catch {
                        errors.append("Toggle \(preset.id): \(error.localizedDescription)")
                    }
                } else {
                    // .3105
                    patchStore.importPackage(at: fileURL)
                }
            }

            DispatchQueue.main.async {
                isPatching = false
                if errors.isEmpty {
                    showSuccess = true
                } else {
                    patchError = errors.joined(separator: "\n")
                }
            }
        }
    }

    private func openApp() {
        let sel = NSSelectorFromString("defaultWorkspace")
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              cls.responds(to: sel),
              let workspace = cls.perform(sel)?.takeUnretainedValue() as? NSObject else { return }
        let openSel = NSSelectorFromString("openApplicationWithBundleID:")
        if workspace.responds(to: openSel) {
            _ = workspace.perform(openSel, with: app.bundleID)
        }
    }
}
