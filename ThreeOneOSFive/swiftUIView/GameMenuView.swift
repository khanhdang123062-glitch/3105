import SwiftUI

struct GameMenuView: View {
    @State private var started = false
    @State private var espEnabled = false
    @State private var aimbotEnabled = false
    @State private var target: AimTarget = .head

    enum AimTarget: String, CaseIterable, Identifiable {
        case head = "Đầu"
        case neck = "Cổ"
        case body = "Thân"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .head:
                return "scope"
            case .neck:
                return "circle"
            case .body:
                return "figure.stand"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    startSection
                    featuresSection
                    targetSection
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Game Menu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("3105")
                .font(.system(size: 34, weight: .black, design: .rounded))

            Text("GAME MENU")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var startSection: some View {
        menuCard {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STATUS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Text(started ? "Running" : "Stopped")
                            .font(.headline)
                    }

                    Spacer()

                    Circle()
                        .fill(started ? .green : .gray)
                        .frame(width: 10, height: 10)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        started.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: started ? "stop.fill" : "play.fill")

                        Text(started ? "STOP" : "START")
                            .fontWeight(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(started ? .red : .blue)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var featuresSection: some View {
        menuCard {
            VStack(spacing: 0) {
                Toggle(isOn: $espEnabled) {
                    featureRow(
                        icon: "viewfinder",
                        title: "ESP",
                        subtitle: "Visual overlay"
                    )
                }
                .padding(.vertical, 5)

                divider

                Toggle(isOn: $aimbotEnabled) {
                    featureRow(
                        icon: "scope",
                        title: "Aimbot",
                        subtitle: "Target selection"
                    )
                }
                .padding(.vertical, 5)
            }
        }
    }

    private var targetSection: some View {
        menuCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("AIM TARGET")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                ForEach(AimTarget.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            target = item
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .frame(width: 24)

                            Text(item.rawValue)
                                .font(.headline)

                            Spacer()

                            Image(
                                systemName:
                                    target == item
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .font(.system(size: 20))
                            .foregroundStyle(
                                target == item
                                ? .blue
                                : .secondary
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if item != AimTarget.allCases.last {
                        divider
                    }
                }
            }
        }
    }

    private func featureRow(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }

    private func menuCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
    }
}

#Preview {
    NavigationStack {
        GameMenuView()
    }
}
