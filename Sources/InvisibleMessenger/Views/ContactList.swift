import MessengerCore
import SwiftUI

/// Layout B: a narrow list on the left with presence dots and unread counts.
struct ContactList: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.contacts) { contact in
                    Button { model.selectedContactID = contact.id } label: {
                        HStack(spacing: 7) {
                            PresenceDot(online: model.isOnline(contact.id))
                            Text(contact.name)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                                .foregroundStyle(contact.id == model.selectedContactID ? Color.white : Theme.textPrimary.opacity(0.8))
                            Spacer(minLength: 2)
                            if contact.unreadCount > 0 {
                                Text("\(contact.unreadCount)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(contact.id == model.selectedContactID ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { model.openPairing() } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(8)
        }
        .frame(width: 132)
    }
}

/// Layout A: contacts as chips across the top.
struct ContactTabs: View {
    let model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.contacts) { contact in
                    Button { model.selectedContactID = contact.id } label: {
                        HStack(spacing: 6) {
                            PresenceDot(online: model.isOnline(contact.id))
                            Text(contact.unreadCount > 0 ? "\(contact.name) · \(contact.unreadCount)" : contact.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .foregroundStyle(contact.id == model.selectedContactID ? Color.white : Theme.textPrimary.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(contact.id == model.selectedContactID ? Theme.selected : Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button { model.openPairing() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24, height: 22)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
