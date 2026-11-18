import SwiftUI

struct SettingsDetailView: View {
    @ObservedObject var viewModel: SettingsViewModel

    let general: GeneralSettingsViewModel
    let connection: ConnectionSettingsViewModel
    let receiving: ReceivingSettingsViewModel

    var body: some View {
        switch viewModel.section {
        case .general: GeneralSettingsView(viewModel: general)
        case .connection: ConnectionSettingsView(viewModel: connection)
        case .receiving: ReceivingSettingsView(viewModel: receiving)
        case .about: AboutSettingsView(viewModel: viewModel)
        }
    }
}
