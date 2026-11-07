import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.mainMenu = AppDelegate.makeMainMenu()
HiddenWindowGuard.install()
app.run()
