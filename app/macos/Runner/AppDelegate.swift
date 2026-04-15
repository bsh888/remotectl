import Cocoa
import FlutterMacOS

// Global flag updated by Flutter via MethodChannel when the agent starts/stops.
// Read by MainFlutterWindow.performClose to decide whether to show a dialog.
var agentIsRunning = false

@main
class AppDelegate: FlutterAppDelegate {

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Register the MethodChannel so Flutter can update agentIsRunning.
    if let vc = mainFlutterWindow?.contentViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: "remotectl/window",
        binaryMessenger: vc.engine.binaryMessenger
      ).setMethodCallHandler { call, result in
        if call.method == "setAgentRunning" {
          agentIsRunning = call.arguments as? Bool ?? false
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
