import AppKit
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct AppearanceTile: View {
    let mode: PKYAppearance.Mode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: PKYLayout.Gap.content()) {
                preview
                    .frame(height: SettingsMetrics.appearancePreviewHeight)
                    .clipShape(RoundedRectangle(
                        cornerRadius: PKYShape.Radius.tile,
                        style: .continuous
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: PKYShape.Radius.tile, style: .continuous)
                            .strokeBorder(
                                Color(nsColor: .pkySeparator(.standard)),
                                lineWidth: PKYShape.Stroke.standard
                            )
                            .opacity(isSelected ? 0 : 1)
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: PKYShape.Radius.tile + SettingsMetrics.appearanceRingOutset,
                            style: .continuous
                        )
                        .strokeBorder(
                            Color(nsColor: .pkyAccent(.primary)),
                            lineWidth: PKYShape.Stroke.strong
                        )
                        .padding(-SettingsMetrics.appearanceRingOutset)
                        .opacity(isSelected ? 1 : 0)
                    )
                Text(Self.title(of: mode))
                    .font(
                        Font(
                            (
                                isSelected ? PKYTypographyRole.supporting.semibold : .supporting
                            ).nsFont(
                                in: PKYThemeFallback.system,
                                referenceSize: SettingsMetrics.compactLabelPointSize
                            )
                        )
                    )
                    .foregroundStyle(
                        Color(nsColor: .pkyContent(isSelected ? .primary : .secondary))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(of: mode))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .system:
            ZStack {
                AppearancePreviewScene(appearance: .aqua)
                AppearancePreviewScene(appearance: .darkAqua)
                    .mask(DiagonalHalf())
            }
        case .light:
            AppearancePreviewScene(appearance: .aqua)
        case .dark:
            AppearancePreviewScene(appearance: .darkAqua)
        }
    }

    static func title(of mode: PKYAppearance.Mode) -> String {
        switch mode {
        case .system: L10n.text("Follow System")
        case .light: L10n.text("Light")
        case .dark: L10n.text("Dark")
        }
    }
}

private struct AppearancePreviewScene: View {
    let appearance: NSAppearance.Name

    private var elevation: PKYElevation.Appearance {
        appearance == .darkAqua ? .dark : .light
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        resolved { NSColor.systemBlue.blended(
                            withFraction: 1 - PKYOpacity.tint,
                            of: .windowBackgroundColor
                        ) },
                        resolved { NSColor.systemOrange.blended(
                            withFraction: 1 - PKYOpacity.tint,
                            of: .windowBackgroundColor
                        ) },
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RoundedRectangle(
                    cornerRadius: SettingsMetrics.appearancePaneCornerRadius,
                    style: .continuous
                )
                .fill(resolved { .pkyBackground(.grouped(.secondary)) })
                .frame(
                    width: proxy.size.width * SettingsMetrics.appearancePaneWidthFraction,
                    height: SettingsMetrics.appearancePaneHeight
                )
                .shadow(
                    color: resolved { PKYThemeFallback.system.color.shadow }
                        .opacity(PKYElevation.Style.subtle.recipe(for: elevation).opacity),
                    radius: PKYElevation.Style.subtle.recipe(for: elevation).radius,
                    y: PKYElevation.Style.subtle.recipe(for: elevation).offset.height
                )
                .padding(.vertical, PKYLayout.Inset.control.horizontal(.compact))
                .padding(.horizontal, PKYLayout.Inset.control.horizontal())
            }
        }
    }

    private func resolved(_ color: () -> NSColor?) -> Color {
        var result = Color.clear
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            result = Color(nsColor: color()?.usingColorSpace(.sRGB) ?? .clear)
        }
        return result
    }
}

private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
