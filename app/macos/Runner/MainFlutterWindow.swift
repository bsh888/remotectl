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
    let w = min(1200.0, (vis.width  * 0.80).rounded())
    let h = min(800.0,  (vis.height * 0.80).rounded())
    let x = vis.minX + (vis.width  - w) / 2
    let y = vis.minY + (vis.height - h) / 2
    self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)

    super.awakeFromNib()
  }
}
