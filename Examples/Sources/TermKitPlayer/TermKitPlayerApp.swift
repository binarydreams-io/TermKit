import Foundation
import TermKit

@main
@MainActor
struct TermKitPlayerApp {
  static func main() async throws {
    let artwork = try loadPlayerArtwork()
    let timeSource = ContinuousTimeSource()
    let model = PlayerModel(timeSource: timeSource)
    let coordinator = PlayerApplicationCoordinator()
    let commands = makePlayerCommands(model: model, coordinator: coordinator)
    let environment = TerminalEnvironment.makeCurrent()
    let capabilities = TerminalCapabilityDetector.capabilities(
      from: environment,
      terminfoHintProvider: nil,
      terminfoHintPolicy: TerminfoHintPolicy(),
      allowsOSC52: false
    )
    let transport = TerminalTransport()
    let session = TerminalSession(transport: transport, capabilities: capabilities)
    let size = try TerminalSizeReader(fileDescriptor: transport.outputFileDescriptor).read()
    let eventSource = try TerminalEventSource(inputFileDescriptor: transport.inputFileDescriptor)
    let runtime = Runtime(
      view: PlayerView(model: model, artwork: artwork),
      presenter: FramePresenter(session: session),
      terminalSize: CellSize(width: size.columns, height: size.rows),
      timeSource: timeSource,
      eventSource: eventSource,
      commands: commands,
      onInput: { _ in try coordinator.processQuitRequest() }
    )
    coordinator.runtime = runtime
    try await runtime.run()
  }
}

@MainActor
final class PlayerApplicationCoordinator {
  weak var runtime: Runtime?
  private(set) var quitRequested = false

  func requestQuit() {
    quitRequested = true
  }

  func processQuitRequest() throws {
    guard quitRequested else { return }
    quitRequested = false
    try runtime?.stop()
  }
}

@MainActor
func makePlayerCommands(model: PlayerModel, coordinator: PlayerApplicationCoordinator) -> KeyboardCommandSet {
  KeyboardCommandSet([
    KeyboardCommand(id: "play-pause", title: "Play or pause", shortcut: KeyboardShortcut(.character(" "))) {
      model.togglePlayback()
    },
    KeyboardCommand(id: "next", title: "Next track", shortcut: KeyboardShortcut(.character("n"))) {
      model.nextTrack()
    },
    KeyboardCommand(id: "previous", title: "Previous track", shortcut: KeyboardShortcut(.character("p"))) {
      model.previousTrack()
    },
    KeyboardCommand(id: "seek-back", title: "Seek backward", shortcut: KeyboardShortcut(.left)) {
      model.seek(by: .seconds(-5))
    },
    KeyboardCommand(id: "seek-forward", title: "Seek forward", shortcut: KeyboardShortcut(.right)) {
      model.seek(by: .seconds(5))
    },
    KeyboardCommand(id: "volume-up", title: "Increase volume", shortcut: KeyboardShortcut(.character("+"))) {
      model.changeVolume(by: 0.05)
    },
    KeyboardCommand(id: "volume-down", title: "Decrease volume", shortcut: KeyboardShortcut(.character("-"))) {
      model.changeVolume(by: -0.05)
    },
    KeyboardCommand(id: "mute", title: "Toggle mute", shortcut: KeyboardShortcut(.character("m"))) {
      model.toggleMute()
    },
    KeyboardCommand(id: "shuffle", title: "Toggle shuffle", shortcut: KeyboardShortcut(.character("s"))) {
      model.toggleShuffle()
    },
    KeyboardCommand(id: "repeat", title: "Cycle repeat", shortcut: KeyboardShortcut(.character("r"))) {
      model.cycleRepeatMode()
    },
    KeyboardCommand(id: "quit", title: "Quit", shortcut: KeyboardShortcut(.character("q"))) {
      coordinator.requestQuit()
    },
    KeyboardCommand(id: "escape", title: "Close or quit", shortcut: KeyboardShortcut(.escape)) {
      coordinator.requestQuit()
    }
  ])
}

func loadPlayerArtwork() throws -> PlayerArtwork {
  guard let pngURL = Bundle.module.url(forResource: "blue-hour", withExtension: "png"),
        let jpegURL = Bundle.module.url(forResource: "signal-drift", withExtension: "jpg")
  else { throw PlayerResourceError.missingArtwork }
  return try PlayerArtwork(
    png: RasterImage(contentsOf: pngURL),
    jpeg: RasterImage(contentsOf: jpegURL)
  )
}

private enum PlayerResourceError: Error {
  case missingArtwork
}
