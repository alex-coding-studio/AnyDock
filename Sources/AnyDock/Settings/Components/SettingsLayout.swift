import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PKYLayout.Gap.section()) {
                VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                    Text(title)
                        .font(typography.display.bold.font)
                    Text(subtitle)
                        .font(typography.body.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PKYLayout.Inset.page(.wide))
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: PKYLayout.Gap.content()) {
            SettingsGroupTitle(title: title)
            content
        }
    }
}

struct SettingsGroupTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Font(PKYTypographyRole.supporting.semibold.nsFont(
                in: PKYThemeFallback.system,
                referenceSize: SettingsMetrics.compactLabelPointSize
            )))
            .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
            .padding(.leading, PKYLayout.Gap.content(.compact))
    }
}

struct SettingsCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PKYShape.Radius.compact, style: .continuous)
            .fill(Color(nsColor: .pkyBackground(.grouped(.secondary))))
            .overlay(
                RoundedRectangle(cornerRadius: PKYShape.Radius.compact, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .pkySeparator(.standard)),
                        lineWidth: PKYShape.Stroke.standard
                    )
            )
    }
}

struct SettingsCard<Content: View>: View {
    enum Padding {
        case rows
        case content
    }

    var padding = Padding.rows
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: padding == .rows ? 0 : PKYLayout.Gap.group(.compact)) {
            content
        }
        .padding(
            .horizontal,
            padding == .rows ? PKYLayout.Inset.row.horizontal(.compact) : PKYLayout.Inset.container()
        )
        .padding(
            .vertical,
            padding == .rows ? PKYLayout.Inset.row.vertical(.compact) : PKYLayout.Inset.container()
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsCardBackground())
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: PKYLayout.Gap.group(.compact)) {
            VStack(alignment: .leading, spacing: PKYLayout.Gap.content(.compact)) {
                Text(title)
                    .font(typography.body.font)
                if let detail {
                    Text(detail)
                        .font(typography.supporting.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
                .fixedSize()
        }
        .frame(minHeight: PKYLayout.Size.row(detail == nil ? .compact : .standard))
    }
}

struct SettingsMessageText: View {
    let message: SettingsMessage?

    init(_ message: SettingsMessage?) {
        self.message = message
    }

    init(error: String?) {
        message = error.map { SettingsMessage(text: $0, isError: true) }
    }

    var body: some View {
        if let message {
            Text(message.text)
                .font(typography.supporting.font)
                .foregroundStyle(
                    Color(
                        nsColor: message.isError ? .pkyStatus(.destructive) : .pkyContent(
                            .secondary
                        )
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PKYLayout.Gap.content(.compact))
        }
    }
}

struct SettingsNote: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PKYLayout.Gap.content(.compact)) {
            Image(systemName: symbol)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(typography.supporting.font)
        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
    }
}
