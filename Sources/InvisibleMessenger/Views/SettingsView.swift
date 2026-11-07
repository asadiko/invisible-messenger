import SwiftUI

struct SettingsView: View {
    let model: AppModel
    var chrome: ChatChrome

    var body: some View {
        VStack {
            Button("Back") { model.screen = .chat }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
