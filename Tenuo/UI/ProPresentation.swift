import SwiftUI

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.9)
            .foregroundStyle(Color(red: 0.24, green: 0.23, blue: 0.30))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.95, blue: 1),
                        Color(red: 0.72, green: 0.71, blue: 0.82),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
            }
            .fixedSize()
            .accessibilityLabel("Tenuo Pro")
    }
}

struct ProFeaturePrompt: View {
    enum Presentation { case card, popover }

    let title: String
    let detail: String
    var visual: String = "square.stack.3d.up"
    var presentation: Presentation = .card
    let activate: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch presentation {
        case .popover:
            content.padding(20)
        case .card:
            content
                .padding(18)
                .background(
                    DS.Surface.raised,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.Line.hairline, lineWidth: 0.5)
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProBadge()
                Spacer()
                Text("Included with Tenuo Pro")
                    .font(DS.Typography.footnote).foregroundStyle(DS.Ink.tertiary)
            }
            ProFeaturePreview(symbol: visual)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Ink.primary)
                Text(detail).font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Button {
                    guard let url = URL(string: "https://tenuo.app/#pricing") else { return }
                    openURL(url)
                } label: {
                    HStack {
                        Spacer()
                        Text("Get Tenuo Pro")
                        Image(systemName: "arrow.up.right").font(
                            .system(size: 11, weight: .semibold))
                        Spacer()
                    }
                }
                .buttonStyle(RoundedActionStyle(prominent: true))
                Button(action: activate) {
                    Text("Already purchased? Activate license")
                        .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                        .padding(.vertical, 4).frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ProFeaturePreview: View {
    var symbol: String

    var body: some View {
        HStack(spacing: 14) {
            if symbol == "icloud" {
                device("laptopcomputer", name: "MacBook")
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18)).foregroundStyle(DS.Ink.tertiary)
                device("desktopcomputer", name: "Desktop Mac")
            } else if symbol == "clock.arrow.circlepath" {
                Image(systemName: symbol).font(.system(size: 32, weight: .light))
                    .foregroundStyle(DS.Ink.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text("An earlier setup").font(DS.Typography.label)
                    Text("Ready to restore").font(DS.Typography.footnote).foregroundStyle(
                        DS.Ink.tertiary)
                }
            } else {
                Keycap(
                    label: symbol == "app.dashed" ? "S" : "F", width: 44, height: 46,
                    legendSize: 16, isLit: true)
                Image(systemName: "arrow.right").foregroundStyle(DS.Ink.tertiary)
                if symbol == "app.dashed" {
                    ApplicationIcon(bundleID: "com.apple.Safari", size: 44)
                } else {
                    Image(systemName: symbol).font(.system(size: 30, weight: .light))
                        .foregroundStyle(DS.Ink.secondary).frame(width: 44, height: 46)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func device(_ symbol: String, name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light))
                .foregroundStyle(DS.Ink.primary)
            Text(name).font(.system(size: 10)).foregroundStyle(DS.Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
