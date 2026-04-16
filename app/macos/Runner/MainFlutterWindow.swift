import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {

  private var channel: FlutterMethodChannel?

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

    // Set up MethodChannel.  Flutter calls "confirmClose" when the user
    // confirms the exit dialog; we then actually close the window.
    channel = FlutterMethodChannel(
      name: "remotectl/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "confirmClose" {
        result(nil)
        self?.close()
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  // Intercept the red ✕ close button (and Cmd+W).
  // Instead of closing immediately, ask Flutter to handle the confirmation.
  // Flutter will call back "confirmClose" if the user agrees.
  override func performClose(_ sender: Any?) {
    channel?.invokeMethod("windowCloseRequested", arguments: nil)
    // Do NOT call super — Flutter decides whether to close.
  }
}
