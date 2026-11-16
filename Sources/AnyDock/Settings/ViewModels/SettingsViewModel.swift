import Combine

@MainActor
final class SettingsViewModel {
    let about: AboutInfo

    private let sectionSubject = CurrentValueSubject<SettingsSection, Never>(.general)
    private let statusSubject = CurrentValueSubject<ListenerStatus, Never>(
        ListenerStatus(.starting)
    )
    private var subscriptions = Set<AnyCancellable>()

    var section: AnyPublisher<SettingsSection, Never> {
        sectionSubject.eraseToAnyPublisher()
    }

    var listenerStatus: AnyPublisher<ListenerStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    init(status: AnyPublisher<InboxStatus, Never>, about: AboutInfo) {
        self.about = about
        status
            .map(ListenerStatus.init)
            .sink { [weak self] in self?.statusSubject.send($0) }
            .store(in: &subscriptions)
    }

    func select(_ section: SettingsSection) {
        guard section != sectionSubject.value else {
            return
        }
        sectionSubject.send(section)
    }
}
