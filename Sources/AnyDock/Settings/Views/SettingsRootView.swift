import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel

    let general: GeneralSettingsViewModel
    let connection: ConnectionSettingsViewModel
    let receiving: ReceivingSettingsViewModel

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            switch viewModel.section {
            case .general: GeneralSettingsView(viewModel: general)
            case .connection: ConnectionSettingsView(viewModel: connection)
            case .receiving: ReceivingSettingsView(viewModel: receiving)
            case .about: AboutSettingsView(about: viewModel.about)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SettingsSidebar: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var selection: Binding<SettingsSection?> {
        Binding(
            get: { viewModel.section },
            set: { section in
                if let section {
                    viewModel.select(section)
                }
            }
        )
    }

    private var statusColor: Color {
        viewModel.listenerStatus.tone == .pending
            ? Color(nsColor: .pkyContent(
                .secondary
            )) : StatusDot.color(viewModel.listenerStatus.tone)
    }

    var body: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(Optional(section))
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(L10n.text("Settings sections"))
        .safeAreaInset(edge: .top, spacing: PKYLayout.Gap.group()) { header }
        .safeAreaInset(edge: .bottom) { version }
    }

    private var header: some View {
        HStack(spacing: PKYLayout.Gap.content()) {
            Image(nsImage: BrandIcon.artwork ?? BrandIcon.menuBar())
                .resizable()
                .frame(
                    width: SettingsMetrics.sidebarAppIconSide,
                    height: SettingsMetrics.sidebarAppIconSide
                )
            VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                Text(L10n.text("AnyDock"))
                    .font(typography.heading.font)
                HStack(spacing: PKYLayout.Gap.content()) {
                    StatusDot(tone: viewModel.listenerStatus.tone)
                    Text(viewModel.listenerStatus.summary)
                        .font(typography.supporting.medium.font)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .help(
                    viewModel.listenerStatus.tone == .failed ? viewModel.listenerStatus.detail : ""
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PKYLayout.Inset.page())
        .padding(.top, PKYLayout.Gap.content())
    }

    @ViewBuilder
    private var version: some View {
        if let version = viewModel.about.version {
            Text(version)
                .font(typography.caption.font)
                .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PKYLayout.Inset.page())
                .padding(.bottom, PKYLayout.Inset.page())
        }
    }
}
