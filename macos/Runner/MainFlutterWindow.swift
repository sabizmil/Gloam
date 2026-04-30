import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Frameless chrome: traffic lights float over a Flutter-drawn top strip.
    // The Flutter content extends under the titlebar; the strip is responsible
    // for drag region (via window_manager) and double-click zoom.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    // `chat.gloam/platform` — dock badge + window focus from notification tap.
    let channel = FlutterMethodChannel(
      name: "chat.gloam/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setBadge":
        let label = (call.arguments as? [String: Any?])?["label"] as? String
        // Empty string or nil clears the dock tile label.
        NSApp.dockTile.badgeLabel = (label?.isEmpty ?? true) ? nil : label
        result(nil)
      case "focusWindow":
        // Brings the app to the foreground; un-minimizes if needed.
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
          if window.isMiniaturized {
            window.deminiaturize(nil)
          }
          window.makeKeyAndOrderFront(nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
