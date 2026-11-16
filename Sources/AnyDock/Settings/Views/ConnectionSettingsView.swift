import AppKit
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct ConnectionSettingsView: View {
    @ObservedObject var viewModel: ConnectionSettingsViewModel

    private var nameBinding: Binding<String> {
        Binding(get: { viewModel.state.shortcutName }, set: viewModel.setShortcutName)
    }

    var body: some View {
        SettingsPage(
            title: SettingsSection.connection.title,
            subtitle: L10n.text("settings.connection.subtitle")
        ) {
            VStack(alignment: .leading, spacing: PKYLayout.Gap.content()) {
                hero
                SettingsMessageText(viewModel.state.message)
            }
            SettingsGroup(title: L10n.text("Manual Setup")) {
                manualCard
                SettingsNote(symbol: "shield", text: L10n.text("settings.manual.note"))
                    .padding(.horizontal, PKYLayout.Gap.content(.compact))
            }
        }
    }

    private var hero: some View {
        HStack(spacing: PKYLayout.Gap.group(.wide)) {
            HeroIllustration()
            VStack(alignment: .leading, spacing: PKYLayout.Gap.group(.compact)) {
                VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                    Text(L10n.text("One-step Setup"))
                        .font(typography.title.font)
                    Text(L10n.text("settings.oneStep.description"))
                        .font(typography.body.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                    Text(L10n.text("Shortcut name"))
                        .font(typography.supporting.semibold.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                    HStack(spacing: PKYLayout.Gap.content()) {
                        TextField(L10n.text("Shortcut name"), text: nameBinding)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .disabled(viewModel.state.isSending)
                        Button(action: viewModel.send) {
                            Label(
                                L10n.text("Send to iPhone…"),
                                systemImage: "antenna.radiowaves.left.and.right"
                            )
                        }
                        .settingsButton(.primary)
                        .buttonBorderShape(.capsule)
                        .disabled(!viewModel.state.canSend)
                    }
                    .controlSize(.large)
                    SettingsMessageText(viewModel.state.nameMessage)
                }
                SettingsNote(symbol: "lock", text: L10n.text("settings.shortcut.note"))
            }
        }
        .padding(PKYLayout.Inset.container(.wide))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PKYShape.Radius.content, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .pkyAccent(.primary)).opacity(PKYOpacity.tint),
                            Color(nsColor: .systemPurple).opacity(PKYOpacity.tint / 2),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: PKYShape.Radius.content, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .pkySeparator(.standard)),
                    lineWidth: PKYShape.Stroke.standard
                )
        )
    }

    private var manualCard: some View {
        SettingsCard {
            manualRow(L10n.text("Receive address")) {
                Text(viewModel.state.receiveAddress)
                    .textSelection(.enabled)
                    .truncationMode(.middle)
                    .help(viewModel.state.receiveAddress)
            } action: {
                Button(L10n.text("Copy"), action: viewModel.copyReceiveAddress)
                    .settingsButton(.secondary)
                    .accessibilityLabel(L10n.text("Copy receive address"))
            }
            Divider()
            manualRow(L10n.text("Connection key")) {
                Text(verbatim: "•••• •••• •••• ••••")
            } action: {
                Button(L10n.text("Copy"), action: viewModel.copyConnectionKey)
                    .settingsButton(.secondary)
                    .accessibilityLabel(L10n.text("Copy connection key"))
            }
            Divider()
            manualRow(L10n.text("Generic shortcut")) {
                Text(L10n.text("Send to Mac"))
                    .font(typography.body.font)
            } action: {
                Button(L10n.text("Export…"), action: exportShortcut)
                    .settingsButton(.secondary)
            }
        }
    }

    private func manualRow(
        _ title: String,
        @ViewBuilder value: () -> some View,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(spacing: PKYLayout.Gap.group(.compact)) {
            Text(title)
                .font(typography.body.font)
                .frame(width: SettingsMetrics.manualLabelWidth, alignment: .leading)
            value()
                .font(typography.supporting.font.monospaced())
                .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .frame(minHeight: PKYLayout.Size.row(.compact))
    }

    private func exportShortcut() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L10n.text("Send to Mac") + ".shortcut"
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        viewModel.exportGenericShortcut(to: destination)
    }
}
