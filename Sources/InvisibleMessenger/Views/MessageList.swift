import MessengerCore
import SwiftUI

struct MessageList: View {
    let model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.messages) { message in
                        MessageRow(message: message, model: model)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: model.selectedContactID) { _, _ in
                if let last = model.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }
}
