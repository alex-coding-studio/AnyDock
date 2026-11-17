import AnyDockCore
import AppKit
import PockyFoundation
import SwiftUI
import UniformTypeIdentifiers

private let typography = PKYThemeFallback.system.typography

struct ReceivingSettingsView: View {
    @ObservedObject var viewModel: ReceivingSettingsViewModel

    private var folderIcon: NSImage {
        let path = viewModel.state.folder.path
        return FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path) : NSWorkspace.shared.icon(for: .folder)
    }

    var body: some View {
        SettingsPage(
            title: SettingsSection.receiving.title,
            subtitle: L10n.text("settings.receiving.subtitle")
        ) {
            statusBanner
            SettingsGroup(title: L10n.text("Save Location")) {
                folderCard
                SettingsMessageText(error: viewModel.state.folderReadError)
                SettingsNote(symbol: "info.circle", text: L10n.text("settings.folder.note"))
                    .padding(.horizontal, PKYLayout.Gap.content(.compact))
            }
            SettingsGroup(title: L10n.text("Network")) {
                networkCard
                SettingsMessageText(error: viewModel.state.errorMessage)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.state.hasChanges {
                bottomBar
            }
        }
    }

    private var statusBanner: some View {
        let status = viewModel.state.status
        let tint = StatusDot.color(status.tone)
        return HStack(spacing: PKYLayout.Gap.group(.compact)) {
            Circle()
                .fill(tint.opacity(PKYOpacity.tint))
                .frame(
                    width: SettingsMetrics.statusBadgeSide,
                    height: SettingsMetrics.statusBadgeSide
                )
                .overlay(StatusDot(tone: status.tone, side: SettingsMetrics.statusBadgeDotSide))
            VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                Text(status.title)
                    .font(Font(PKYTypographyRole.heading.nsFont(
                        in: PKYThemeFallback.system,
                        referenceSize: SettingsMetrics.emphasisTitlePointSize
                    )))
                    .foregroundStyle(
                        Color(
                            nsColor: status.tone == .failed ? .pkyStatus(.destructive) : .pkyContent(
                                .primary
                            )
                        )
                    )
                if !status.detail.isEmpty {
                    Text(status.detail)
                        .font(typography.body.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, PKYLayout.Inset.row.vertical(.wide))
        .padding(.horizontal, PKYLayout.Inset.row.horizontal())
        .background(
            RoundedRectangle(cornerRadius: PKYShape.Radius.content, style: .continuous)
                .fill(tint.opacity(PKYOpacity.tint / 2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PKYShape.Radius.content, style: .continuous)
                .strokeBorder(tint.opacity(PKYOpacity.tint), lineWidth: PKYShape.Stroke.standard)
        )
        .accessibilityElement(children: .combine)
    }

    private var folderCard: some View {
        SettingsCard(padding: .content) {
            HStack(spacing: PKYLayout.Gap.group(.compact)) {
                Image(nsImage: folderIcon)
                    .resizable()
                    .frame(
                        width: SettingsMetrics.folderIconSide,
                        height: SettingsMetrics.folderIconSide
                    )
                VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                    Text(viewModel.state.folderName)
                        .font(Font(PKYTypographyRole.heading.nsFont(
                            in: PKYThemeFallback.system,
                            referenceSize: SettingsMetrics.emphasisTitlePointSize
                        )))
                    Text(viewModel.state.folderPath)
                        .font(typography.body.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                        .help(viewModel.state.folder.path)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.text("Show in Finder"), action: showInFinder)
                    .settingsButton(.secondary)
                Button(L10n.text("Change…"), action: chooseFolder)
                    .settingsButton(.secondary)
            }
            HStack(spacing: PKYLayout.Gap.content()) {
                Text(L10n.text("Sorted by type"))
                    .font(typography.supporting.font)
                    .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                ForEach(ReceivedKind.allCases, id: \.self) { kind in
                    SettingsChip(kind: kind)
                        .help(kind.directoryName + "/")
                }
            }
        }
    }

    private var networkCard: some View {
        SettingsCard {
            SettingsRow(
                title: L10n.text("Listening port"),
                detail: L10n.text(
                    "meta_separator",
                    L10n.text("settings.port.range"),
                    L10n.text("settings.port.note")
                )
            ) {
                TextField(
                    String(ConnectionConfiguration.Receiver.defaultPort),
                    text: Binding(
                        get: { viewModel.state.portText },
                        set: { viewModel.setPortText($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(typography.body.font.monospaced())
                .multilineTextAlignment(.center)
                .frame(width: SettingsMetrics.portFieldWidth)
                .accessibilityLabel(L10n.text("Listening port"))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: PKYLayout.Gap.content()) {
            Circle()
                .fill(Color(nsColor: .pkyStatus(.warning)))
                .frame(width: PKYLayout.Size.dot(), height: PKYLayout.Size.dot())
            Text(viewModel.state.pendingMessage)
                .font(typography.body.font)
                .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.text("Revert"), action: { viewModel.revert() })
                .settingsButton(.secondary)
                .disabled(viewModel.state.isApplying)
            Button(L10n.text("Apply"), action: { viewModel.apply() })
                .settingsButton(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.state.canApply)
        }
        .padding(.vertical, PKYLayout.Inset.row.vertical(.wide))
        .padding(.horizontal, PKYLayout.Inset.page(.wide))
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([viewModel.state.folder])
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.state.folder
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.selectFolder(url)
        }
    }
}
