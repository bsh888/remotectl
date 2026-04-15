import Cocoa
import FlutterMacOS

// Updated by Flutter via MethodChannel when the agent starts/stops (or locale changes).
// Read by MainFlutterWindow.performClose to decide whether to show a dialog and
// which localized strings to display.
var agentIsRunning      = false
var closeDialogTitle    = "退出确认"
var closeDialogMessage  = "当前正在共享屏幕，退出后远程连接将断开。"
var closeDialogQuit     = "停止共享并退出"
var closeDialogCancel   = "取消"

@main
class AppDelegate: FlutterAppDelegate {

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Register the MethodChannel so Flutter can update agentIsRunning and
    // the localized dialog strings whenever the agent starts/stops or the
    // user switches language.
    if let vc = mainFlutterWindow?.contentViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: "remotectl/window",
        binaryMessenger: vc.engine.binaryMessenger
      ).setMethodCallHandler { call, result in
        if call.method == "setAgentRunning",
           let args = call.arguments as? [String: Any] {
          agentIsRunning     = args["running"] as? Bool   ?? agentIsRunning
          closeDialogTitle   = args["title"]   as? String ?? closeDialogTitle
          closeDialogMessage = args["message"] as? String ?? closeDialogMessage
          closeDialogQuit    = args["quit"]    as? String ?? closeDialogQuit
          closeDialogCancel  = args["cancel"]  as? String ?? closeDialogCancel
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
