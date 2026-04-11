import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)

    self.minSize = NSSize(width: 480, height: 600)

    // Start at 80 % of the visible screen area, capped at 1200 × 800.
    // This prevents the window from being larger than smaller Mac screens
    // (e.g. 13-inch MacBook at 1280 × 800 logical points).
    let screen = NSScreen.main ?? NSScreen.screens.first!
    let vis = screen.visibleFrame
    self.setFrame(vis, display: true)

    super.awakeFromNib()
  }
}
