import AnyDockCore
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { viewModel.state.language }, set: viewModel.selectLanguage)
    }

    var body: some View {
        SettingsPage(
            title: SettingsSection.general.title,
            subtitle: L10n.text("settings.general.subtitle")
        ) {
            SettingsGroup(title: L10n.text("Appearance")) {
                appearanceCard
                SettingsMessageText(error: viewModel.state.restartMessage)
            }
            HStack(alignment: .top, spacing: PKYLayout.Gap.group()) {
                SettingsGroup(title: L10n.text("Tray")) {
                    trayCard
                }
                .frame(maxWidth: .infinity)
                SettingsGroup(title: L10n.text("Startup & Keyboard")) {
                    startupCard
                    SettingsMessageText(error: viewModel.state.loginMessage)
                    SettingsMessageText(error: viewModel.state.hotKeyMessage)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(padding: .content) {
            HStack(spacing: PKYLayout.Gap.group(.compact)) {
                ForEach(PKYAppearance.Mode.allCases, id: \.self) { mode in
                    AppearanceTile(mode: mode, isSelected: viewModel.state.appearance == mode) {
                        viewModel.selectAppearance(mode)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("Appearance"))
            Divider()
            HStack {
                Text(L10n.text("Language"))
                    .font(typography.body.font)
                Spacer()
                Picker(L10n.text("Language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(Self.title(of: language)).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if viewModel.state.showsRestartNotice {
                restartNotice
            }
        }
    }

    private var restartNotice: some View {
        HStack(spacing: PKYLayout.Gap.content()) {
            Group {
                Image(systemName: "arrow.clockwise")
                Text(L10n.text("Restart AnyDock to apply the language change."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(nsColor: .pkyAccent(.primary)))
            Button(L10n.text("Restart Now"), action: viewModel.restart)
                .settingsButton(.primary)
        }
        .font(typography.body.font)
        .padding(.vertical, PKYLayout.Inset.control.vertical())
        .padding(.horizontal, PKYLayout.Inset.control.horizontal())
        .background(
            RoundedRectangle(cornerRadius: PKYShape.Radius.tile, style: .continuous)
                .fill(Color(nsColor: .pkyAccent(.primary)).opacity(PKYOpacity.tint))
        )
    }

    private var trayCard: some View {
        SettingsCard {
            SettingsRow(title: L10n.text("Copy new items automatically")) {
                Toggle(
                    L10n.text("Copy new items automatically"),
                    isOn: Binding(
                        get: { viewModel.state.copiesNewItems },
                        set: { viewModel.setCopiesNewItems($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Divider()
            SettingsRow(
                title: L10n.text("Keep last 4 clipboard texts"),
                detail: L10n.text("settings.clipboardHistory.note")
            ) {
                Toggle(
                    L10n.text("Keep last 4 clipboard texts"),
                    isOn: Binding(
                        get: { viewModel.state.keepsClipboardHistory },
                        set: { viewModel.setKeepsClipboardHistory($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var startupCard: some View {
        SettingsCard {
            SettingsRow(title: L10n.text("Launch at login")) {
                Toggle(
                    L10n.text("Launch at login"),
                    isOn: Binding(
                        get: { viewModel.state.launchesAtLogin },
                        set: { viewModel.setLaunchesAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Divider()
            SettingsRow(title: L10n.text("Wake shortcut")) {
                ShortcutField(viewModel: viewModel)
            }
        }
    }

    private static func title(of language: AppLanguage) -> String {
        switch language {
        case .system: L10n.text("Follow System")
        case .english: L10n.text("English")
        case .simplifiedChinese: L10n.text("简体中文")
        }
    }
}
