import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var section = SettingsSection.general
    @Published private(set) var listenerStatus = ListenerStatus(.starting)

    let about: AboutInfo

    private var subscriptions = Set<AnyCancellable>()

    init(status: AnyPublisher<InboxStatus, Never>, about: AboutInfo) {
        self.about = about
        status
            .map(ListenerStatus.init)
            .sink { [weak self] in self?.listenerStatus = $0 }
            .store(in: &subscriptions)
    }

    func select(_ section: SettingsSection) {
        guard section != self.section else {
            return
        }
        self.section = section
    }
}
