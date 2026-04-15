import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)

    self.minSize = NSSize(width: 480, height: 600)

    // Open at a sensible default size (never fullscreen).
    // Clamp to 90 % of the visible screen so the window fits on small Macs.
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let vis = screen.visibleFrame
    let w = min(1100.0, vis.width  * 0.9)
    let h = min(760.0,  vis.height * 0.9)
    let x = vis.minX + (vis.width  - w) / 2
    let y = vis.minY + (vis.height - h) / 2
    self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)

    super.awakeFromNib()
  }

  // Intercept the red ✕ close button (and Cmd+W) before the window disappears.
  // Overriding performClose: is more reliable than NSWindowDelegate.windowShouldClose:
  // because it fires synchronously on user action regardless of who the delegate is.
  override func performClose(_ sender: Any?) {
    guard agentIsRunning else {
      super.performClose(sender)
      return
    }

    let alert = NSAlert()
    alert.messageText     = closeDialogTitle
    alert.informativeText = closeDialogMessage
    alert.addButton(withTitle: closeDialogQuit)
    alert.addButton(withTitle: closeDialogCancel)
    alert.alertStyle = .warning

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      super.performClose(sender)
    }
    // else: user cancelled — window stays open, do nothing
  }
}
