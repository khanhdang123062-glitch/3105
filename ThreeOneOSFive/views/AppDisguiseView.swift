import SwiftUI
import UIKit
import PhotosUI

struct AppDisguiseView: View {
    let app: InstalledApp

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showResetConfirm = false

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

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(radius: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.secondary)
                                )
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text(selectedImage == nil ? "Chọn ảnh" : "Đổi ảnh")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } header: {
                Text("Icon mới")
            } footer: {
                Text("Chọn ảnh bất kỳ từ thư viện để làm icon.")
            }
            .onChange(of: selectedPhoto) { item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        selectedImage = img
                    }
                }
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
                    (displayName.isEmpty || selectedImage == nil)
                        ? Color.secondary : AppTheme.accent
                )
                .disabled(displayName.isEmpty || selectedImage == nil || isApplying)

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
        guard let image = selectedImage, !displayName.isEmpty else { return }
        isApplying = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AppDisguiseService.apply(
                    bundleID: app.bundleID,
                    displayName: displayName,
                    iconName: "custom",
                    iconImage: image
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
                selectedImage = nil
            }
        }
    }
}
