import SwiftUI

/// Colours matching the hardware notch (pure black) with dark surfaces on top.
enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.047)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let surfaceHigh = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let separator = Color.white.opacity(0.07)
    static let bubbleIncoming = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let bubbleOutgoing = Color(red: 0.165, green: 0.384, blue: 0.788)
    static let accent = Color(red: 0.29, green: 0.66, blue: 1.0)
    static let online = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let offline = Color.gray.opacity(0.6)
    static let hidden = Color(red: 0.50, green: 0.82, blue: 0.55)
    static let selected = Color(red: 0.13, green: 0.23, blue: 0.34)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.5)
    static let codeBackground = Color(red: 0.08, green: 0.08, blue: 0.095)
    static let codeText = Color(red: 0.81, green: 0.89, blue: 1.0)
}

/// Small icon button used across the chat chrome (no tooltips: they would be separate, capturable windows).
struct IconButton: View {
    let systemName: String
    var tint: Color = Theme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HiddenBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash.fill").font(.system(size: 9))
            Text("Hidden").font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(Theme.hidden)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.hidden.opacity(0.12), in: Capsule())
    }
}

struct PresenceDot: View {
    let online: Bool
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(online ? Theme.online : Theme.offline)
            .frame(width: size, height: size)
    }
}

extension Notification.Name {
    /// Posted when the chat opens so the message box takes keyboard focus.
    static let focusComposer = Notification.Name("InvisibleMessenger.focusComposer")
}
