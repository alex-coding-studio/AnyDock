import Combine

@MainActor
protocol UpdateChecking: AnyObject {
    var availability: AnyPublisher<Bool, Never> { get }
    func checkForUpdates()
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var section = SettingsSection.general
    @Published private(set) var listenerStatus = ListenerStatus(.starting)

    @Published private(set) var canCheckForUpdates = false

    let about: AboutInfo

    private let updates: (any UpdateChecking)?

    private var subscriptions = Set<AnyCancellable>()

    init(
        status: AnyPublisher<InboxStatus, Never>,
        about: AboutInfo,
        updates: (any UpdateChecking)? = nil
    ) {
        self.updates = updates
        self.about = about
        updates?.availability.assign(to: &$canCheckForUpdates)
        status
            .map(ListenerStatus.init)
            .sink { [weak self] in self?.listenerStatus = $0 }
            .store(in: &subscriptions)
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            return
        }
        updates?.checkForUpdates()
    }

    func select(_ section: SettingsSection) {
        guard section != self.section else {
            return
        }
        self.section = section
    }
}
