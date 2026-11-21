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
