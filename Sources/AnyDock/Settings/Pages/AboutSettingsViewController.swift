import AppKit
import PockyFoundation
import SnapKit

@MainActor
final class AboutSettingsViewController: NSViewController {
    private let about: AboutInfo

    init(about: AboutInfo) {
        self.about = about
        super.init(nibName: nil, bundle: nil)
        title = SettingsSection.about.title
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let icon = NSImageView(image: BrandIcon.artwork ?? BrandIcon.menuBar())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.snp.makeConstraints { $0.size.equalTo(SettingsMetrics.aboutAppIconSide) }
        let name = SettingsLabel.make(L10n.text("AnyDock"), font: PKYTypographyRole.pageTitle.bold)
        let tagline = SettingsLabel.make(L10n.text("about.tagline"), color: .pkyContent(.secondary))
        let versionLabel = SettingsLabel.make(
            about.version ?? "",
            font: PKYTypographyRole.supporting.monospacedDigits,
            color: .pkyContent(.secondary)
        )
        versionLabel.isSelectable = true
        let version = CapsuleView(views: [versionLabel])
        version.isHidden = about.version == nil
        let links = NSStackView(views: [
            linkButton(
                L10n.text("GitHub Project"),
                symbol: "chevron.left.forwardslash.chevron.right",
                action: #selector(openRepository)
            ),
            linkButton(
                L10n.text("Author @Cunqi"),
                symbol: "person.crop.circle",
                action: #selector(openAuthor)
            ),
        ])
        links.orientation = .horizontal
        links.spacing = PKYLayout.Gap.content()
        let identity = NSStackView(views: [icon, name, tagline, version, links])
        identity.orientation = .vertical
        identity.alignment = .centerX
        identity.spacing = PKYLayout.Gap.content()
        identity.setCustomSpacing(PKYLayout.Gap.group(), after: icon)
        identity.setCustomSpacing(PKYLayout.Gap.group(), after: version)
        let quit = NSButton(
            title: L10n.text("Quit AnyDock"),
            target: NSApp,
            action: #selector(NSApplication.terminate(_:))
        )
        quit.bezelStyle = .push
        let copyright = SettingsLabel.make(
            L10n.text("about.copyright"),
            font: .supporting,
            color: .pkyContent(.secondary)
        )
        let bottom = NSStackView(views: [copyright, NSView(), quit])
        bottom.orientation = .horizontal
        let separator = NSBox()
        separator.boxType = .separator
        let content = NSView(frame: NSRect(origin: .zero, size: SettingsMetrics.windowContentSize))
        for view in [identity, separator, bottom] {
            content.addSubview(view)
        }
        identity.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-PKYLayout.Gap.section())
            make.leading.greaterThanOrEqualToSuperview().inset(PKYLayout.Inset.page(.wide))
        }
        bottom.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(PKYLayout.Inset.page(.wide))
            make.bottom.equalToSuperview().inset(PKYLayout.Inset.page())
            make.top.greaterThanOrEqualTo(identity.snp.bottom).offset(PKYLayout.Gap.section())
        }
        separator.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottom.snp.top).offset(-PKYLayout.Inset.page())
        }
        view = content
    }

    private func linkButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = SettingsLabel.button(title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .push
        return button
    }

    @objc private func openRepository() {
        AboutInfo.repositoryURL.map { _ = NSWorkspace.shared.open($0) }
    }

    @objc private func openAuthor() {
        AboutInfo.authorURL.map { _ = NSWorkspace.shared.open($0) }
    }
}
