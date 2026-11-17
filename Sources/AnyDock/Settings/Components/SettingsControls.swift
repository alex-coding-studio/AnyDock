import AnyDockCore
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

enum SettingsButtonRole {
    case primary
    case secondary
}

extension View {
    @ViewBuilder
    func settingsButton(_ role: SettingsButtonRole) -> some View {
        switch role {
        case .primary: buttonStyle(.borderedProminent)
        case .secondary: buttonStyle(.bordered)
        }
    }
}

struct SettingsChip: View {
    let symbol: String
    let title: String

    init(symbol: String, title: String) {
        self.symbol = symbol
        self.title = title
    }

    init(kind: ReceivedKind) {
        symbol = switch kind {
        case .image: "photo"
        case .text: "text.alignleft"
        case .link: "link"
        case .file: "doc"
        }
        title = kind.directoryName
    }

    var body: some View {
        HStack(spacing: PKYLayout.Gap.content(.compact)) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(typography.supporting.font)
        .padding(.vertical, PKYLayout.Inset.control.vertical(.compact))
        .padding(.horizontal, PKYLayout.Inset.control.horizontal(.compact))
        .background(
            Capsule().fill(Color(nsColor: PKYThemeFallback.system.color.filled.quiet(.tertiary)))
        )
        .fixedSize()
    }
}

struct StatusDot: View {
    let tone: ListenerStatus.Tone
    var side = PKYLayout.Size.dot()

    var body: some View {
        Circle()
            .fill(Self.color(tone))
            .frame(width: side, height: side)
            .background(
                Circle().fill(Self.color(tone).opacity(
                    PKYOpacity.tint
                )).padding(-PKYShape.Stroke.heavy)
            )
    }

    static func color(_ tone: ListenerStatus.Tone) -> Color {
        switch tone {
        case .pending: Color(nsColor: .pkyContent(.tertiary))
        case .listening: Color(nsColor: .pkyStatus(.success))
        case .failed: Color(nsColor: .pkyStatus(.destructive))
        }
    }
}
