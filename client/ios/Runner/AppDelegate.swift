import CoreMotion
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so tapped reminders reach the
    // plugin while the app is running. The plugin's README puts this in
    // didFinishLaunchingWithOptions; it does not depend on the implicit
    // Flutter engine, so it does not need to wait for
    // didInitializeImplicitFlutterEngine below.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StepsPlugin") {
      StepsPlugin.register(with: registrar)
    }
  }
}

/// The phone's own step counter (Core Motion), not Apple Health: it needs
/// only the Motion & Fitness permission and keeps the last seven days.
final class StepsPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let pedometer = CMPedometer()
  private var sink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = StepsPlugin()
    let methods = FlutterMethodChannel(name: "fitsync/steps", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    FlutterEventChannel(name: "fitsync/steps/live", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(CMPedometer.isStepCountingAvailable())
    case "stepsBetween":
      guard let args = call.arguments as? [String: Any],
            let fromMs = (args["fromMs"] as? NSNumber)?.doubleValue,
            let toMs = (args["toMs"] as? NSNumber)?.doubleValue else {
        result(FlutterError(code: "bad_args", message: "fromMs and toMs required", details: nil))
        return
      }
      guard CMPedometer.isStepCountingAvailable() else {
        result(FlutterError(code: "unavailable", message: "Step counting not available", details: nil))
        return
      }
      pedometer.queryPedometerData(
        from: Date(timeIntervalSince1970: fromMs / 1000),
        to: Date(timeIntervalSince1970: toMs / 1000)
      ) { data, error in
        DispatchQueue.main.async {  // the handler is not on the main queue
          if let error = error as NSError? {
            result(FlutterError(code: "cm_error", message: error.localizedDescription, details: error.code))
          } else {
            result(data?.numberOfSteps.intValue ?? 0)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CMPedometer.isStepCountingAvailable() else {
      return FlutterError(code: "unavailable", message: "Step counting not available", details: nil)
    }
    let fromMs = ((arguments as? [String: Any])?["fromMs"] as? NSNumber)?.doubleValue
    let from = fromMs.map { Date(timeIntervalSince1970: $0 / 1000) }
      ?? Calendar.current.startOfDay(for: Date())
    sink = events
    pedometer.startUpdates(from: from) { [weak self] data, error in
      DispatchQueue.main.async {
        guard let sink = self?.sink else { return }
        if let error = error as NSError? {
          sink(FlutterError(code: "cm_error", message: error.localizedDescription, details: error.code))
        } else if let data = data {
          sink(data.numberOfSteps.intValue)  // cumulative since `from`
        }
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pedometer.stopUpdates()
    sink = nil
    return nil
  }
}
