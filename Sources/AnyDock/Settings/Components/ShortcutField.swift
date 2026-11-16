import AppKit
import Combine
import PockyFoundation
import SwiftUI

private let typography = PKYThemeFallback.system.typography

struct ShortcutField: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: PKYLayout.Gap.content(.compact)) {
            field
                .overlay(HotKeyRecorderBridge(viewModel: viewModel))
            if viewModel.state.hotKey != nil {
                Button(action: viewModel.clearHotKey) {
                    Image(systemName: "xmark")
                        .font(typography.supporting.semibold.font)
                        .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
                        .padding(PKYLayout.Gap.content(.compact))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.text("hotkey.clear"))
                .accessibilityLabel(L10n.text("hotkey.clear.accessibility"))
            }
        }
    }

    private var field: some View {
        Group {
            if viewModel.state.isRecordingHotKey {
                prompt(L10n.text("Type shortcut…"))
            } else if let hotKey = viewModel.state.hotKey {
                HStack(spacing: PKYLayout.Gap.content(.compact)) {
                    ForEach(Array(hotKey.displayKeys.enumerated()), id: \.offset) { _, key in
                        keyCap(key)
                    }
                }
            } else {
                prompt(L10n.text("hotkey.placeholder"))
            }
        }
        .padding(PKYLayout.Inset.control.vertical(.compact))
        .background(
            RoundedRectangle(cornerRadius: PKYShape.Radius.tile, style: .continuous)
                .fill(Color(nsColor: PKYThemeFallback.system.color.filled.quiet(.tertiary)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PKYShape.Radius.tile, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .pkyAccent(.primary)),
                    lineWidth: viewModel.state.isRecordingHotKey ? PKYShape.Stroke.strong : 0
                )
        )
        .accessibilityHidden(true)
    }

    private func prompt(_ text: String) -> some View {
        Text(text)
            .font(typography.supporting.font)
            .foregroundStyle(Color(nsColor: .pkyContent(.secondary)))
            .padding(.vertical, PKYLayout.Inset.control.vertical(.compact))
            .padding(.horizontal, PKYLayout.Inset.control.horizontal(.compact))
    }

    private func keyCap(_ key: String) -> some View {
        let recipe = PKYElevation.Style.subtle.recipe(for: colorScheme == .dark ? .dark : .light)
        return Text(key)
            .font(typography.supporting.font)
            .padding(.vertical, PKYLayout.Inset.control.vertical(.compact))
            .padding(.horizontal, PKYLayout.Inset.control.horizontal(.compact))
            .frame(minWidth: SettingsMetrics.keyCapMinWidth)
            .background(
                RoundedRectangle(
                    cornerRadius: SettingsMetrics.keyCapCornerRadius,
                    style: .continuous
                )
                .fill(Color(nsColor: .pkyBackground(.grouped(.secondary))))
                .shadow(
                    color: Color(nsColor: PKYThemeFallback.system.color.shadow).opacity(
                        recipe.opacity
                    ),
                    radius: 0,
                    y: recipe.offset.height
                )
            )
    }
}

private struct HotKeyRecorderBridge: NSViewRepresentable {
    @MainActor
    final class Coordinator {
        private var subscriptions = Set<AnyCancellable>()

        func bind(_ recorder: HotKeyRecorder, to viewModel: GeneralSettingsViewModel) {
            recorder.recordingChanges
                .sink { [weak viewModel] recording in
                    if recording {
                        viewModel?.beginHotKeyRecording()
                    } else {
                        viewModel?.endHotKeyRecording()
                    }
                }
                .store(in: &subscriptions)
            recorder.records
                .sink { [weak viewModel] in viewModel?.record($0) }
                .store(in: &subscriptions)
            recorder.rejections
                .sink { [weak viewModel] in viewModel?.rejectHotKey() }
                .store(in: &subscriptions)
        }
    }

    let viewModel: GeneralSettingsViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HotKeyRecorder {
        let recorder = HotKeyRecorder()
        recorder.isTransparent = true
        recorder.focusRingType = .none
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            recorder.setContentHuggingPriority(.fittingSizeCompression, for: orientation)
            recorder.setContentCompressionResistancePriority(
                .fittingSizeCompression,
                for: orientation
            )
        }
        context.coordinator.bind(recorder, to: viewModel)
        return recorder
    }

    func updateNSView(_ recorder: HotKeyRecorder, context _: Context) {
        recorder.hotKey = viewModel.state.hotKey
        if !viewModel.state.isRecordingHotKey, recorder.isRecording {
            Task { @MainActor in recorder.endRecording() }
        }
    }
}
