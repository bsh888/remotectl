import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {

  // Set to true by Flutter (via MethodChannel) when the agent is running.
  var agentRunning = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Become the window delegate so we can intercept the close button.
    NSApp.windows.first?.delegate = self

    // Register the MethodChannel used by Flutter to update agentRunning.
    if let vc = mainFlutterWindow?.contentViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: "remotectl/window",
        binaryMessenger: vc.engine.binaryMessenger
      ).setMethodCallHandler { [weak self] call, result in
        if call.method == "setAgentRunning" {
          self?.agentRunning = call.arguments as? Bool ?? false
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  // Called when the user clicks the red ✕ close button.
  // Return false to cancel the close; true to allow it.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard agentRunning else { return true }

    let alert = NSAlert()
    alert.messageText    = NSLocalizedString("stop_sharing_title",    comment: "Stop Sharing")
    alert.informativeText = NSLocalizedString("stop_sharing_message", comment: "Agent is running. Quit and stop sharing?")
    alert.addButton(withTitle: NSLocalizedString("stop_sharing_quit",   comment: "Quit"))
    alert.addButton(withTitle: NSLocalizedString("stop_sharing_cancel", comment: "Cancel"))
    alert.alertStyle = .warning

    let response = alert.runModal()
    // First button = "Quit" → allow close; second = "Cancel" → stay open.
    return response == .alertFirstButtonReturn
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
