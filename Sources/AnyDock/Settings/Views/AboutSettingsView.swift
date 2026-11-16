import AppKit
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct AboutSettingsView: View {
    let about: AboutInfo

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: PKYLayout.Gap.section())
            identity
            Spacer(minLength: PKYLayout.Gap.section())
            Divider()
            HStack {
                Text(L10n.text("about.copyright"))
                    .font(typography.supporting.font)
                    .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                Spacer()
                Button(action: { NSApp.terminate(nil) }) {
                    Text(L10n.text("Quit AnyDock"))
                        .foregroundStyle(Color(nsColor: .pkyStatus(.destructive)))
                }
                .settingsButton(.secondary)
            }
            .padding(.vertical, PKYLayout.Inset.page())
        }
        .padding(.horizontal, PKYLayout.Inset.page(.wide))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identity: some View {
        VStack(spacing: 0) {
            Image(nsImage: BrandIcon.artwork ?? BrandIcon.menuBar())
                .resizable()
                .frame(
                    width: SettingsMetrics.aboutAppIconSide,
                    height: SettingsMetrics.aboutAppIconSide
                )
                .background(
                    Circle()
                        .fill(Color(nsColor: .pkyAccent(.primary)).opacity(PKYOpacity.dimmed))
                        .blur(radius: SettingsMetrics.aboutIconGlowRadius)
                )
            Text(L10n.text("AnyDock"))
                .font(typography.display.bold.font)
                .padding(.top, PKYLayout.Gap.group())
            Text(L10n.text("about.tagline"))
                .font(typography.title.regular.font)
                .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                .padding(.top, PKYLayout.Gap.content(.compact))
            if let version = about.version {
                Text(version)
                    .font(typography.supporting.medium.font)
                    .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                    .textSelection(.enabled)
                    .padding(.vertical, PKYLayout.Inset.control.vertical(.compact))
                    .padding(.horizontal, PKYLayout.Inset.control.horizontal(.compact))
                    .background(
                        Capsule().fill(
                            Color(nsColor: PKYThemeFallback.system.color.filled.quiet(.tertiary))
                        )
                    )
                    .padding(.top, PKYLayout.Gap.group(.compact))
            }
            HStack(spacing: PKYLayout.Gap.content()) {
                link(
                    L10n.text("GitHub Project"),
                    symbol: "chevron.left.forwardslash.chevron.right",
                    url: AboutInfo.repositoryURL
                )
                link(
                    L10n.text("Author @Cunqi"),
                    symbol: "person.crop.circle",
                    url: AboutInfo.authorURL
                )
            }
            .padding(.top, PKYLayout.Gap.section())
        }
    }

    private func link(_ title: String, symbol: String, url: URL?) -> some View {
        Button {
            url.map { _ = NSWorkspace.shared.open($0) }
        } label: {
            Label(title, systemImage: symbol)
                .font(typography.body.semibold.font)
        }
        .settingsButton(.secondary)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}
