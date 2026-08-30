import SwiftUI
import UIKit

private struct DisguisePreset: Identifiable {
    let id: String
    let name: String
    let systemIcon: String
    let color: Color
}

private let presets: [DisguisePreset] = [
    DisguisePreset(id: "calculator", name: "Calculator", systemIcon: "function", color: .orange),
    DisguisePreset(id: "calendar", name: "Calendar", systemIcon: "calendar", color: .red),
    DisguisePreset(id: "clock", name: "Clock", systemIcon: "clock.fill", color: .black),
    DisguisePreset(id: "notes", name: "Notes", systemIcon: "note.text", color: .yellow),
    DisguisePreset(id: "weather", name: "Weather", systemIcon: "cloud.sun.fill", color: .blue),
    DisguisePreset(id: "settings", name: "Settings", systemIcon: "gearshape.fill", color: .gray),
    DisguisePreset(id: "maps", name: "Maps", systemIcon: "map.fill", color: .green),
    DisguisePreset(id: "health", name: "Health", systemIcon: "heart.fill", color: .pink),
    DisguisePreset(id: "music", name: "Music", systemIcon: "music.note", color: .red),
    DisguisePreset(id: "photos", name: "Photos", systemIcon: "photo.fill", color: .purple),
    DisguisePreset(id: "safari", name: "Safari", systemIcon: "safari.fill", color: .blue),
    DisguisePreset(id: "files", name: "Files", systemIcon: "folder.fill", color: .blue),
]

struct AppDisguiseView: View {
    let app: InstalledApp

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var selectedPreset: DisguisePreset?
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showResetConfirm = false

    private let columns = [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible())
    ]

    var body: some View {
        Form {
            Section {
                TextField("Tên hiển thị mới", text: $displayName)
                    .autocorrectionDisabled()
            } header: {
                Text("Tên app")
            } footer: {
                Text("Tên này sẽ hiện dưới icon \(app.displayName) trên màn hình chính.")
            }

            Section("Chọn icon ngụy trang") {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(presets) { preset in
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(preset.color)
                                    .frame(width: 60, height: 60)
                                Image(systemName: preset.systemIcon)
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        selectedPreset?.id == preset.id
                                            ? Color.accentColor : Color.clear,
                                        lineWidth: 3
                                    )
                            )
                            .onTapGesture {
                                selectedPreset = preset
                                if displayName.isEmpty {
                                    displayName = preset.name
                                }
                            }
                            Text(preset.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                Button(action: applyDisguise) {
                    HStack {
                        Spacer()
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Áp dụng")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                }
                .listRowBackground(
                    (displayName.isEmpty || selectedPreset == nil)
                        ? Color.secondary : AppTheme.accent
                )
                .disabled(displayName.isEmpty || selectedPreset == nil || isApplying)

                if AppDisguiseService.currentConfig(bundleID: app.bundleID) != nil {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Khôi phục tên & icon gốc")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            } footer: {
                Text("Sau khi áp dụng vuốt lên màn hình chính để thấy thay đổi.")
            }
        }
        .navigationTitle("Ngụy trang \(app.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let config = AppDisguiseService.currentConfig(bundleID: app.bundleID) {
                displayName = config.displayName
                selectedPreset = presets.first { $0.id == config.iconName }
            }
        }
        .alert("Lỗi", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Đã áp dụng!", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("Icon và tên \(app.displayName) đã thay đổi.")
        }
        .confirmationDialog(
            "Khôi phục về gốc?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Khôi phục", role: .destructive) { resetDisguise() }
            Button("Huỷ", role: .cancel) {}
        }
    }

    private func applyDisguise() {
        guard let preset = selectedPreset, !displayName.isEmpty else { return }
        isApplying = true
        let iconImage = makeIcon(systemName: preset.systemIcon, color: preset.color)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AppDisguiseService.apply(
                    bundleID: app.bundleID,
                    displayName: displayName,
                    iconName: preset.id,
                    iconImage: iconImage
                )
                DispatchQueue.main.async {
                    isApplying = false
                    showSuccess = true
                }
            } catch {
                DispatchQueue.main.async {
                    isApplying = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resetDisguise() {
        DispatchQueue.global(qos: .userInitiated).async {
            try? AppDisguiseService.reset(bundleID: app.bundleID)
            DispatchQueue.main.async {
                displayName = ""
                selectedPreset = nil
            }
        }
    }

    private func makeIcon(systemName: String, color: Color) -> UIImage {
        let size = CGSize(width: 180, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor(color).setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: 40
            ).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 80, weight: .medium)
            if let symbol = UIImage(systemName: systemName, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let x = (size.width - symbol.size.width) / 2
                let y = (size.height - symbol.size.height) / 2
                symbol.draw(at: CGPoint(x: x, y: y))
            }
        }
    }
}
