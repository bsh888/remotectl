import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {

  private var channel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)

    self.minSize = NSSize(width: 480, height: 600)

    // Open at a sensible default size (never fullscreen).
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let vis = screen.visibleFrame
    let w = min(1100.0, vis.width  * 0.9)
    let h = min(760.0,  vis.height * 0.9)
    let x = vis.minX + (vis.width  - w) / 2
    let y = vis.minY + (vis.height - h) / 2
    self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)

    super.awakeFromNib()

    // Set delegate AFTER super so we override whatever Flutter may have set.
    self.delegate = self

    // MethodChannel: Flutter calls "confirmClose" to actually close the window.
    channel = FlutterMethodChannel(
      name: "remotectl/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "confirmClose" {
        result(nil)
        // close() bypasses windowShouldClose — no recursion risk.
        self?.close()
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Called synchronously when the user clicks ✕ (or Cmd+W).
  // Always return false to block the default close; ask Flutter instead.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    channel?.invokeMethod("windowCloseRequested", arguments: nil)
    return false
  }
}
