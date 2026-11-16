struct ListenerStatus: Equatable {
    enum Tone: Equatable {
        case pending
        case listening
        case failed
    }

    let tone: Tone
    let summary: String
    let title: String
    let detail: String

    init(_ status: InboxStatus) {
        switch status {
        case .starting:
            tone = .pending
            summary = L10n.text("Starting")
            title = L10n.text("Starting the receiver…")
            detail = ""
        case let .listening(port):
            tone = .listening
            summary = L10n.text("Listening · %@", String(port))
            title = L10n.text("Listening on port %@", String(port))
            detail = L10n.text("settings.receiving.listening.detail")
        case let .failed(message):
            tone = .failed
            summary = L10n.text("Receiver Failed")
            title = L10n.text("Receiver Failed")
            detail = message
        }
    }
}
