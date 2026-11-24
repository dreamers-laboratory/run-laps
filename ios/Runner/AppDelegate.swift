import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var player: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "laps")!.messenger()
    FlutterMethodChannel(name: "laps", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "bell": result(self?.ring((call.arguments as! FlutterStandardTypedData).data))
      case "saver", "canSave": result(false)  // Low Power Mode is the user's switch on iPhone
      default: result(nil)
      }
    }
  }

  /// The bell is 16-bit mono PCM at 44.1 kHz; it plays over music without pausing it.
  private func ring(_ pcm: Data) -> Bool {
    func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    let header: [Data] = [
      Data("RIFF".utf8), le(UInt32(36 + pcm.count)), Data("WAVEfmt ".utf8), le(UInt32(16)), le(UInt16(1)),
      le(UInt16(1)), le(UInt32(44100)), le(UInt32(88200)), le(UInt16(2)), le(UInt16(16)), Data("data".utf8),
      le(UInt32(pcm.count)),
    ]
    let wav = header.reduce(Data(), +) + pcm
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
    player = try? AVAudioPlayer(data: wav)
    return player?.play() ?? false
  }
}
