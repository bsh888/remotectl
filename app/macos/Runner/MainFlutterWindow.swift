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
}
