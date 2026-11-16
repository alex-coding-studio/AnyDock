import PockyFoundation
import SwiftUI

struct HeroIllustration: View {
    var body: some View {
        HStack(spacing: PKYLayout.Gap.content()) {
            Image(systemName: "iphone")
                .foregroundStyle(Color(nsColor: .pkyContent(.primary)))
            Image(systemName: "wave.3.right")
                .foregroundStyle(Color(nsColor: .pkyAccent(.primary)))
            Image(systemName: "laptopcomputer")
                .foregroundStyle(Color(nsColor: .pkyContent(.primary)))
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: SettingsMetrics.heroCheckmarkPointSize, weight: .bold))
                        .foregroundStyle(Color(nsColor: .pkyAccent(.primary)))
                )
        }
        .font(.system(size: SettingsMetrics.heroIllustrationPointSize, weight: .light))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("settings.oneStep.illustration"))
    }
}
