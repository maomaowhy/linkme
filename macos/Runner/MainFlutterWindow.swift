import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let fileSystemChannel = FlutterMethodChannel(
      name: "link_me/file_system",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    fileSystemChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "openDirectory":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          result(false)
          return
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        result(NSWorkspace.shared.open(url))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
