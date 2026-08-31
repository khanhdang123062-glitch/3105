import SwiftUI

struct GameMenuView: View {
    let app: InstalledApp
    @ObservedObject var patchStore: PatchProjectStore
    @Environment(\.appLanguage) private var language

    @State private var enabledRules: Set<UUID> = []
    @State private var isPatching = false
    @State private var patchError: String?
    @State private var showSuccess = false

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
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerSection

                // Toggle list
                ScrollView {
                    VStack(spacing: 0) {
                        if allRules.isEmpty {
                            emptyState
                        } else {
                            toggleList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Start button
                startButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initEnabledRules() }
        .alert("Đã mod thành công!", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        }
        .alert("Lỗi", isPresented: Binding(
            get: { patchError != nil },
            set: { if !$0 { patchError = nil } }
        )) {
            Button("OK", role: .cancel) { patchError = nil }
        } message: {
            Text(patchError ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text("MENU")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .kerning(3)
                Spacer()
            }

            Text(app.displayName.uppercased())
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            // Hack button
            Button(action: applyHack) {
                HStack(spacing: 8) {
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
                .frame(width: 120, height: 36)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(isPatching || allRules.isEmpty)
            .padding(.top, 4)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.1)),
            alignment: .bottom
        )
    }

    // MARK: - Toggle List

    private var toggleList: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("PATCH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .kerning(2)
                Spacer()
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(allRules.enumerated()), id: \.element.rule.id) { index, pair in
                    let rule = pair.rule
                    let ruleName = ruleDisplayName(rule: rule, index: index)

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            // Index badge
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AppTheme.accent.opacity(0.2))
                                    .frame(width: 28, height: 28)
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppTheme.accent)
                            }

                            Text(ruleName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)

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
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if index < allRules.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 54)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Other section
            HStack {
                Text("OTHER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .kerning(2)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                otherRow(
                    title: "No Recoil",
                    subtitle: "Giảm giật súng",
                    icon: "scope",
                    enabled: false
                )
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 54)
                otherRow(
                    title: "Ghost Mode",
                    subtitle: "Ẩn khỏi minimap",
                    icon: "eye.slash.fill",
                    enabled: false
                )
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
            )

            Text("Các tính năng trong OTHER cần offset — coming soon")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    private func otherRow(title: String, subtitle: String, icon: String, enabled: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange.opacity(0.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
            Spacer()
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .tint(.orange)
                .disabled(true)
                .opacity(0.4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.2))
            Text("Chưa có patch nào\nImport file .3105 từ màn trước")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button(action: openApp) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("START")
                    .font(.system(size: 17, weight: .bold))
                    .kerning(3)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AppTheme.accent.opacity(0.4), radius: 12, x: 0, y: 4)
        }
    }

    // MARK: - Helpers

    private func ruleDisplayName(rule: PatchRule, index: Int) -> String {
        if !rule.replacementFilename.isEmpty {
            return rule.replacementFilename
        }
        let filename = URL(fileURLWithPath: rule.relativePath).lastPathComponent
        return filename.isEmpty ? "Toggle \(index + 1)" : filename
    }

    private func initEnabledRules() {
        enabledRules = Set(allRules.map(\.rule.id))
    }

    private func applyHack() {
        guard !isPatching else { return }
        isPatching = true
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
                }
            } catch {
                DispatchQueue.main.async {
                    isPatching = false
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
