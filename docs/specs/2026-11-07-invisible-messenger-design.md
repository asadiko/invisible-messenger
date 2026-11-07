# Invisible Messenger — Design

Date: 2026-11-07
Status: approved 2026-11-08

## 1. Intent

A private messenger between Macs on the same Wi-Fi that **never appears in screen sharing, screen recordings, or screenshots**. You can keep chatting with a colleague or friend while presenting in Zoom/Meet/Teams, recording a demo, or sharing your whole screen, and nobody watching sees it. Two Macs pair once by typing a short code; after that they find each other automatically and chat end-to-end encrypted, with no server and no internet involved.

## 2. Goals

### 2.1 Always hidden
- Every window the app creates (notch panel, floating window, settings, pairing, image viewer, file picker, confirmation dialogs) is excluded from capture (`NSWindow.sharingType = .none`). This is always on and has **no toggle**.
- Nothing else on screen gives the app away: **no Dock icon, no menu-bar icon, not in Cmd-Tab, no macOS notification banners, no sounds.**
- No native right-click menus or hover tooltips inside the chat. They are separate windows that may not inherit the hiding. Every action is an inline button (Copy, Save, Delete, and so on).
- Spell-check, autocorrect, and text-completion popups are off in the message box.
- **File picker and Save dialogs (my call):**
  - The app isn't sandboxed, so the macOS Open and Save panels run inside the app's own process. That means they can be marked hidden too. The hiding test in §8 checks them.
  - If the test shows they leak anyway, we fall back. 📎 then accepts only paste and drag-in, and **Save** writes straight to a folder chosen in Settings (Downloads by default), with no dialog.

### 2.2 Two appearance modes (switch in Settings)

**Notch mode (default)**
- **Closed:** looks like the plain hardware notch.
- **Unread messages:** the notch shows a soft pulsing blue glow and a small dot. No banner and no sound.
- **Hover:** the notch widens slightly to a "peek" line, for example `Sam · 2 new   [Open]`.
- **Open:** click the notch or press the hotkey, and the chat panel drops down out of the notch.
- **Close:** the `▲ close` tab under the panel, the hotkey, Esc, or clicking anywhere outside the panel. A **pin** button keeps it open while you click other apps.
- **Panel size:**
  - The default width is **3 × the notch width**, centered on the notch: one notch-width to the left, the notch itself, and one to the right. That is 660 pt on the 14" MacBook Pro, whose notch is 220 pt.
  - The default height is 520 pt.
  - The user can **resize** it. Dragging the left or right edge changes the width symmetrically around the notch. Dragging the bottom edge changes the height.
  - The size is remembered, and Settings has a **Reset size** button.
  - Limits: width from 440 pt to 90% of the screen width, and height from 280 pt to 85% of the screen height.
- Opening, peeking, and glowing never steal focus from the app you're presenting in. The panel takes keyboard focus only when you click into it or open it with the hotkey.
- It works over full-screen apps and on every Space.
- **Macs without a notch:** a black, notch-shaped tab at the top center of the main display stands in for the notch. It is 200 pt wide by default, and all sizing rules use that width.
- **With multiple displays,** the panel lives on the display that has the notch, or on the main display if none has one.

**Floating mini window**
- A small, semi-transparent chat panel that always stays on top of other windows. You can move it, resize it, and set its transparency (40–100%) with a slider.
- The hotkey shows and hides it. When it's hidden and a message arrives, the notch (or the stand-in notch tab) glows, as in notch mode.

**Layouts inside the chat (setting)**
- **B. Contact list on the left (default):** a narrow list shows each contact's online dot and unread count, with the chat beside it.
- **A. Contacts as tabs across the top:** the chat uses the full width.
- Both layouts have a header with the contact's name and connection state, a lock button, and a settings button.

### 2.3 Messaging
- **Text messages.**
- **Code blocks:**
  - Typing a fenced block with three backticks (` ``` `), optionally followed by a language, renders a monospaced block with a language label and a one-click **Copy** button.
  - Inline `code` renders monospaced.
  - Syntax colouring is out of scope.
- **Images:** paste, drag in, or use the 📎 attach button.
  - Shown inline as thumbnails.
  - Click a thumbnail to open it in an in-app viewer, which is also hidden.
  - A **Save** button saves the image.
- **Files of any type:** drag in, or use the 📎 button. Each file shows its name and size, with a **Save** button. Transfers show progress.
- **Maximum attachment size:** 100 MB (my call).
- **Message status:** sending, then sent, then delivered.
- **Offline contacts:** messages to a contact who is offline are **queued** and sent automatically when they reconnect.
- **Deleting:** a message (your copy only), or a whole chat. Removing a contact deletes its chat history after a confirmation.

### 2.4 Pairing and connections
- **Adding a contact:**
  1. Mac A clicks **＋ Add**. It shows an **8-character code** (for example `K7Q4-M2XP`) that expires in 5 minutes.
  2. Mac B clicks **＋ Add → Enter code** and types it.
  3. Both Macs show the same **4-emoji check** (for example 🦊🌵🎈🔑). Each user confirms that they match, and the contact is saved on both sides.
- **Wrong codes:** a wrong code fails cleanly. After 3 wrong attempts the code is discarded and a new one must be generated.
- **After pairing**, contacts reconnect automatically whenever both Macs are on the same network and the app is running. There is no code again.
- **Contacts:**
  - You can have several contacts. Each one is a Mac.
  - You can rename or remove them in Settings.
  - Each Mac sets its own display name. It defaults to the Mac's computer name.

### 2.5 Security
- **Direct connections only.** Everything travels directly over the local network. There is no server, cloud, or internet.
- **Encryption in transit:** every connection is **end-to-end encrypted, with forward secrecy**.
- **Authentication:** each side proves its identity with keys that were pinned during pairing. Connections from unknown or changed keys are rejected.
- **The pairing code** is never sent in the clear. A wrong code reveals nothing useful. The emoji check catches an attacker sitting in the middle.
- **Chat history on disk:** messages and attachments are **encrypted at rest**. The key lives in the macOS Keychain.

### 2.6 App lock (setting)
- **Options:** **None (default)**, **Touch ID** (which falls back to the Mac login password), or **App password** (a separate password just for this app).
- **When it locks:**
  - At launch.
  - When the whole Mac has had no keyboard or mouse input for the idle time. The idle time can be set to 5, 15 (default), or 60 minutes, or Never. It is measured across the whole Mac, not just inside the chat, so the app doesn't lock in the middle of a meeting just because you haven't typed into it (my call).
  - When the Mac sleeps or the screen locks.
  - With the manual 🔒 button.
- **While locked:**
  - Messages are still received and stored.
  - The notch still glows.
  - The peek shows only a count (`2 new`), with no names or text.
- **What the lock protects against:** people at your Mac. The disk encryption protects against someone copying your files.

### 2.7 Other
- **Global hotkey** to show or hide the chat. The default is **⌥⌘M** and you can change it in Settings.
- **Settings:**
  - Appearance mode (Notch or Floating)
  - Layout (B or A)
  - Transparency
  - Panel size reset
  - Hotkey
  - App lock and idle time
  - Display name
  - Contacts (rename or remove)
  - Launch at login (off by default)
  - **Delete all data**
  - Quit
- **Quitting:** because the app has no Dock or menu-bar icon, you quit from Settings. Opening the app again while it's running just shows the chat.

## 3. Non-goals (v1)
- Chatting over the internet or between different networks.
- Group chats, voice or video, typing indicators, or read receipts beyond "delivered".
- Editing or unsending messages on the other person's Mac.
- An iPhone or iPad version.
- Syntax highlighting.
- Notarized distribution through the Mac App Store or a website.

## 4. Anti-goals (failure even if it "works")
- **Leaks into captures:** any part of the chat appears in a screen share, recording, or screenshot. That includes popups, menus, tooltips, image previews, and dialogs.
- **Giveaways on the shared screen:** anything else reveals the app there, such as a Dock icon, menu-bar icon, notification banner, or sound.
- **Stolen focus:** the notch or the floating window grabs keyboard focus from the meeting or presentation app when you didn't click it.
- **Weak security:** someone else on the Wi-Fi can read messages, pair without the code, or impersonate a contact.
- **Unreadable sizing:** the panel is too wide or cramped. It must stay at about 3 notch-widths by default.

## 5. Constraints and honest limits
- **Platform:** macOS 26 or later. Both of the user's Macs run macOS 26 or newer, so the minimum is set to 26 (my call; this avoids compatibility code for older systems). Development and testing happen on macOS 26.6 (a 14" MacBook Pro with a notch). The second Mac may not have a notch.
- **No third-party dependencies.** Only Apple frameworks: SwiftUI, AppKit, Network, CryptoKit, Security/Keychain, LocalAuthentication, and Carbon for the global hotkey.
- **Hiding relies on the macOS window-sharing flag.**
  - Screen-sharing apps and screenshots respect it.
  - We must **verify it on macOS 26** with real captures (see §8). This check runs **first, before the main build**.
  - **If some capture path does show the window** (for example, a particular sharing app), the build still goes ahead. The README then states clearly where hiding works and where it doesn't (the user's decision).
  - Things the app doesn't draw can still show up in a share:
    - the macOS Emoji & Symbols picker
    - input-method candidate windows
    - **system prompts**: the Touch ID dialog, the Local Network permission prompt on first launch, and Keychain prompts
  - The **App password** lock is drawn by the app, so it is hidden. The Touch ID dialog may be visible. The README will say this.
- **Network:**
  - Both Macs must be on the same network.
  - Guest or corporate Wi-Fi that isolates devices can block discovery.
  - The app also uses Apple's peer-to-peer Wi-Fi (the AirDrop-style link), so Macs that are physically near each other may still connect.
- **First launch on each Mac:** macOS asks for **Local Network** permission, and the user must allow it.
- **Distribution:**
  - The app is built from source and signed with the user's Apple Development certificate. A stable signature means macOS doesn't keep asking for Keychain access after rebuilds.
  - The second Mac gets a copy of the built `.app`. Because it isn't notarized, the first launch there needs **System Settings › Privacy & Security › Open Anyway**. The README will explain this.

## 6. How it's built (decided)

All of these are **my call**, made because the user handed the technical choices to the builder.
- **App structure:** a native Swift app. SwiftUI views are hosted in AppKit `NSPanel` windows, which are borderless and non-activating for the notch. The app runs as an "accessory" app with no Dock icon.
- **Keyboard shortcuts:** standard editing shortcuts (⌘C, ⌘V, ⌘X, ⌘A, ⌘Z) must work in the message box even though the app has no visible menu bar.
- **Project layout:**
  - A Swift package with:
    - a **core library** (crypto, wire protocol, storage, message parsing) that is fully unit-tested, and
    - the **app**.
  - A build script assembles and signs `Invisible Messenger.app`. Its Info.plist includes the Local Network usage text, the Bonjour service types, and the setting that hides the Dock icon.
- **Discovery:** Bonjour over Network.framework, using the service type `_invmsg._tcp`, with peer-to-peer Wi-Fi enabled.
- **Cryptography** (CryptoKit only):
  - **Identity keys:** each Mac has a long-term identity key pair (Curve25519), stored in the Keychain.
  - **Pairing:**
    - The short code is stretched with PBKDF2.
    - The stretched code authenticates an ephemeral X25519 key exchange. Both sides prove they know the code with a MAC over the handshake transcript.
    - The two Macs then exchange identity keys over the encrypted channel.
    - Each Mac shows a 4-emoji fingerprint derived from both identity keys and the transcript.
    - The contact is saved only after both users confirm the emoji match.
  - **Sessions:**
    - Each connection runs a Noise-style handshake that combines fresh ephemeral keys with the pinned identity keys. This gives mutual authentication and forward secrecy.
    - Frames are then encrypted with ChaCha20-Poly1305 using counters.
- **Storage:**
  - All data lives under `~/Library/Application Support/InvisibleMessenger/`.
  - Message contents and attachments are encrypted with a random 256-bit data key kept in the Keychain.
- **Testability:** a launch option gives an instance its own data folder and Keychain namespace. Two instances can then run on one Mac and pair with each other for end-to-end testing.

## 7. Left to the builder
- **Visual polish** within the mockup direction: colours, spacing, animations, and the glow.
- **Storage format:** for example, an encrypted SQLite database or encrypted per-chat files. It must keep everything content-bearing encrypted and load the latest messages quickly.
- **Wire format details:** message framing, chunk size for attachments, and keep-alives.
- **Choosing which Mac dials** when both are online, so there are no duplicate connections.

## 8. How we'll know it works
- **Hiding check first:** before the main build, a small test window confirms that the window-sharing flag is respected on macOS 26.
  - **Result (2026-11-08, macOS 26.6.2):**
    - A test window with sharing turned off was **absent** from both a `screencapture` screenshot and a ScreenCaptureKit full-display capture. A normal control window was present in both.
    - Capturing that window directly with ScreenCaptureKit was refused by macOS.
- **Unit tests:**
  - Pairing and handshake success.
  - A wrong code fails.
  - Swapping keys in the middle produces different emoji on each side.
  - Unknown or changed keys are rejected.
  - Encryption round-trips.
  - Framing.
  - At-rest encryption: files on disk contain no plaintext.
  - Code-block parsing.
- **Two instances on this Mac:**
  - pair
  - chat
  - send code blocks, images, and files
  - quit and relaunch, then auto-reconnect
  - queue messages while offline
  - lock and unlock
  - resize the notch panel
  - switch modes and layouts
- **Hiding test:** with the panel open, take captures through both the `screencapture` tool and ScreenCaptureKit, the API that modern sharing apps use. Check that the chat's pixels are absent while a normal control window is present. This test requires Screen Recording permission for the terminal, which the user will grant.
- **Manual checks by the user:**
  - Share the screen in Zoom, Meet, or Teams, record with QuickTime, and take a ⌘⇧5 screenshot, with the chat open.
  - Do a real chat between two Macs.
