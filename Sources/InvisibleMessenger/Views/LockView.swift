import SwiftUI

struct LockView: View {
    let model: AppModel
    var chrome: ChatChrome

    var body: some View {
        Text("Locked")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }
}
