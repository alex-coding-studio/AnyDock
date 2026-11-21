import AppKit
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct SettingsSidebar: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var statusColor: Color {
        viewModel.listenerStatus.tone == .pending
            ? Color(nsColor: .pkyContent(
                .secondary
            )) : StatusDot.color(viewModel.listenerStatus.tone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PKYLayout.Gap.group()) {
            header
            navigation
            Spacer(minLength: 0)
            footer
                .padding(.horizontal, PKYLayout.Inset.control.horizontal())
        }
        .padding(.horizontal, PKYLayout.Inset.row.horizontal(.compact))
        .padding(.top, PKYLayout.Gap.content())
        .padding(.bottom, PKYLayout.Inset.page())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: PKYLayout.Gap.content()) {
            if let update = viewModel.availableUpdate {
                Button(L10n.text("New Version Available"), action: viewModel.checkForUpdates)
                    .settingsButton(.primary)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .fixedSize()
                    .help(L10n.text("settings.update.available", update))
            }
            HStack(spacing: PKYLayout.Gap.content()) {
                if let version = viewModel.about.version {
                    Text(version)
                        .font(typography.supporting.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Button(action: { NSApp.terminate(nil) }) {
                    Text(L10n.text("Quit"))
                        .foregroundStyle(Color(nsColor: .pkyStatus(.destructive)))
                }
                .settingsButton(.secondary)
                .controlSize(.small)
                .fixedSize()
                .help(L10n.text("Quit AnyDock"))
                .accessibilityLabel(L10n.text("Quit AnyDock"))
            }
        }
    }

    private var header: some View {
        HStack(spacing: PKYLayout.Gap.content(.wide)) {
            Image(nsImage: BrandIcon.artwork ?? BrandIcon.menuBar())
                .resizable()
                .frame(
                    width: SettingsMetrics.sidebarAppIconSide,
                    height: SettingsMetrics.sidebarAppIconSide
                )
            VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                Text(L10n.text("AnyDock"))
                    .font(Font(PKYTypographyRole.heading.nsFont(
                        in: PKYThemeFallback.system,
                        referenceSize: SettingsMetrics.emphasisTitlePointSize
                    )))
                HStack(alignment: .firstTextBaseline, spacing: PKYLayout.Gap.content()) {
                    StatusDot(tone: viewModel.listenerStatus.tone)
                    Text(viewModel.listenerStatus.summary)
                        .font(typography.supporting.medium.font)
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(
                    viewModel.listenerStatus.tone == .failed ? viewModel.listenerStatus.detail : ""
                )
            }
        }
        .padding(.horizontal, PKYLayout.Gap.content())
        .accessibilityElement(children: .combine)
    }

    private var navigation: some View {
        VStack(spacing: PKYLayout.Gap.content(.compact)) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                row(section)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: move)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Settings sections"))
    }

    private func row(_ section: SettingsSection) -> some View {
        let isSelected = viewModel.section == section
        return Button {
            viewModel.select(section)
        } label: {
            HStack(spacing: PKYLayout.Gap.content(.wide)) {
                Image(systemName: section.symbolName)
                    .font(.system(size: PKYIcon.Size.control.pointSize))
                    .frame(width: PKYIcon.Size.feature.pointSize)
                Text(section.title)
                    .font((isSelected ? typography.body.semibold : typography.body).font)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                Color(nsColor: isSelected ? .pkyAccent(.primary) : .pkyContent(.primary))
            )
            .padding(.horizontal, PKYLayout.Inset.control.horizontal())
            .frame(minHeight: PKYLayout.Size.button(.compact))
            .background(
                RoundedRectangle(cornerRadius: PKYShape.Radius.tile, style: .continuous)
                    .fill(
                        isSelected ? Color(nsColor: .pkyAccent(
                            .primary
                        )).opacity(PKYOpacity.tint) : .clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func move(_ direction: MoveCommandDirection) {
        let sections = SettingsSection.allCases
        guard let index = sections.firstIndex(of: viewModel.section) else {
            return
        }
        switch direction {
        case .up where index > sections.startIndex:
            viewModel.select(sections[index - 1])
        case .down where index < sections.index(before: sections.endIndex):
            viewModel.select(sections[index + 1])
        default:
            break
        }
    }
}
