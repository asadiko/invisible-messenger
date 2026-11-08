import AppKit
import MessengerCore
import SwiftUI

enum NotchPhase: Equatable {
    case closed, peek, open
}

/// What the notch window is showing; owned by `NotchController`.
@Observable
final class NotchViewState {
    var phase: NotchPhase = .closed
    var notchSize: CGSize = CGSize(width: 200, height: 32)
    var hasHardwareNotch = true
    var glowMargin: CGFloat = 0
    var pinned = false
}

struct NotchActions {
    var open: () -> Void
    var close: () -> Void
    var togglePin: () -> Void
    var resizeBegan: () -> Void
    var resizeChanged: (ResizeEdge) -> Void
    var resizeEnded: () -> Void
}

struct NotchRootView: View {
    let model: AppModel
    let state: NotchViewState
    let actions: NotchActions

    static let closeTabHeight: CGFloat = 22

    var body: some View {
        Group {
            switch state.phase {
            case .closed: closed
            case .peek: peek
            case .open: open
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Closed

    private var closed: some View {
        ZStack(alignment: .top) {
            NotchShape(radius: 10)
                .fill(Color.black)
                .frame(width: state.notchSize.width, height: state.notchSize.height)
                .modifier(Glow(active: model.totalUnread > 0))
            if model.totalUnread > 0 {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: state.hasHardwareNotch ? state.notchSize.width / 2 + 7 : state.notchSize.width / 2 - 14,
                            y: state.hasHardwareNotch ? state.notchSize.height - 9 : state.notchSize.height / 2 - 3.5)
            }
        }
        .padding(.horizontal, state.glowMargin)
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.open)
    }

    // MARK: Peek

    private var peek: some View {
        VStack(spacing: 0) {
            Spacer(minLength: state.notchSize.height)
            HStack(spacing: 8) {
                Text(peekText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(Theme.surfaceHigh, in: Capsule())
            }
            .padding(.horizontal, 16)
            .frame(height: 26)
            .padding(.bottom, 4)
        }
        .background(NotchShape(radius: 16).fill(Color.black))
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.open)
    }

    private var peekText: String {
        let unread = model.totalUnread
        guard unread > 0 else { return "Invisible Messenger" }
        if model.isLocked { return "\(unread) new" }
        let name = model.contact(model.lastIncomingFrom)?.name
            ?? model.contacts.first { $0.unreadCount > 0 }?.name
        return name.map { "\($0) · \(unread) new" } ?? "\(unread) new"
    }

    // MARK: Open

    private var open: some View {
        VStack(spacing: 0) {
            PanelContent(model: model, chrome: ChatChrome(
                onClose: actions.close,
                onTogglePin: actions.togglePin,
                isPinned: state.pinned,
                topInset: state.notchSize.height
            ))
            .clipShape(NotchShape(radius: 22))
            .overlay(resizeHandles)
            Button(action: actions.close) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                    Text("close").font(.system(size: 11))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .frame(height: Self.closeTabHeight)
                .background(NotchShape(radius: 10).fill(Theme.background))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var resizeHandles: some View {
        ZStack {
            HStack {
                handle(.left).frame(width: 8)
                Spacer()
                handle(.right).frame(width: 8)
            }
            .padding(.top, state.notchSize.height + 8)
            .padding(.bottom, 24)
            VStack {
                Spacer()
                handle(.bottom).frame(height: 8).padding(.horizontal, 30)
            }
        }
    }

    private func handle(_ edge: ResizeEdge) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .pointerStyle(edge == .bottom ? .frameResize(position: .bottom) : .frameResize(position: edge == .left ? .leading : .trailing))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if value.translation == .zero { actions.resizeBegan() }
                        actions.resizeChanged(edge)
                    }
                    .onEnded { _ in actions.resizeEnded() }
            )
    }
}

/// The chat (or lock screen) inside a panel.
struct PanelContent: View {
    let model: AppModel
    var chrome: ChatChrome

    var body: some View {
        if model.isLocked {
            LockView(model: model, chrome: chrome)
        } else {
            PanelRoot(model: model, chrome: chrome)
        }
    }
}

/// Square top corners (flush with the top of the screen), rounded bottom corners, like the notch.
nonisolated struct NotchShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0))
    }
}

/// A soft pulsing blue glow for unread messages.
private struct Glow: ViewModifier {
    let active: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(color: active ? Theme.accent.opacity(pulse ? 0.9 : 0.35) : .clear, radius: active ? 9 : 0)
            .onAppear { pulse = true }
            .animation(active ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : .default, value: pulse)
    }
}
