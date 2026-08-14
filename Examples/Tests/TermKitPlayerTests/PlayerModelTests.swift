import TermKit
import Testing

@testable import TermKitPlayer

@MainActor
struct PlayerModelTests {
    @Test("Playback clock advances only while playing and clamps at duration")
    func playbackClock() {
        let model = PlayerModel(timeSource: DeterministicTimeSource())

        #expect(model.position(at: .seconds(20)) == .zero)
        model.play()
        #expect(model.position(at: .seconds(20)) == .seconds(20))
        #expect(model.position(at: .seconds(500)) == model.currentTrack.duration)
        model.pause()
        #expect(model.positionAtAnchor == .zero)
    }

    @Test("Transport, seek, volume, and playback modes are deterministic")
    func controls() {
        let model = PlayerModel(timeSource: DeterministicTimeSource())

        model.seek(by: .seconds(5))
        #expect(model.positionAtAnchor == .seconds(5))
        model.seek(by: .seconds(-10))
        #expect(model.positionAtAnchor == .zero)
        model.setProgress(0.5)
        #expect(model.positionAtAnchor == .seconds(model.currentTrack.duration.seconds / 2))
        model.playbackProgressBinding(at: .zero).wrappedValue += 5 / model.currentTrack.duration.seconds
        #expect(model.positionAtAnchor == .seconds(model.currentTrack.duration.seconds / 2 + 5))
        model.nextTrack()
        #expect(model.currentTrack.id == "glass-harbor")
        model.previousTrack()
        #expect(model.currentTrack.id == "blue-hour")
        model.changeVolume(by: 1)
        #expect(model.volume == 1)
        model.toggleMute()
        #expect(model.isMuted)
        model.toggleShuffle()
        #expect(model.isShuffled)
        model.cycleRepeatMode()
        #expect(model.repeatMode == .all)
    }

    @Test("Queue selection and activation keep selected and current tracks distinct")
    func queueSelection() {
        let model = PlayerModel(timeSource: DeterministicTimeSource())

        model.moveSelection(by: 1)
        #expect(model.selectedTrack.id == "glass-harbor")
        #expect(model.currentTrack.id == "blue-hour")
        model.playSelectedTrack()
        #expect(model.currentTrack.id == "glass-harbor")
        #expect(model.isPlaying)

        let queue = PlayerQueueView(model: model, visibleRowCount: 4)
        #expect(queue.activate(at: CellPoint(x: 2, y: 2)))
        #expect(model.currentTrack.id == "static-bloom")
    }

    @Test("Application command set maps the complete global shortcut table")
    func applicationCommands() {
        let model = PlayerModel(timeSource: DeterministicTimeSource())
        let coordinator = PlayerApplicationCoordinator()
        let commands = makePlayerCommands(model: model, coordinator: coordinator)

        #expect(commands.dispatch(KeyboardShortcut(.character(" "))) == "play-pause")
        #expect(model.isPlaying)
        #expect(commands.dispatch(KeyboardShortcut(.right)) == "seek-forward")
        #expect(model.positionAtAnchor == .seconds(5))
        #expect(commands.dispatch(KeyboardShortcut(.left)) == "seek-back")
        #expect(model.positionAtAnchor == .zero)
        #expect(commands.dispatch(KeyboardShortcut(.character("n"))) == "next")
        #expect(model.currentTrack.id == "glass-harbor")
        #expect(commands.dispatch(KeyboardShortcut(.character("p"))) == "previous")
        #expect(model.currentTrack.id == "blue-hour")
        #expect(commands.dispatch(KeyboardShortcut(.character("+"))) == "volume-up")
        #expect(abs(model.volume - 0.7) < 0.000_001)
        #expect(commands.dispatch(KeyboardShortcut(.character("-"))) == "volume-down")
        #expect(abs(model.volume - 0.65) < 0.000_001)
        #expect(commands.dispatch(KeyboardShortcut(.character("m"))) == "mute")
        #expect(model.isMuted)
        #expect(commands.dispatch(KeyboardShortcut(.character("s"))) == "shuffle")
        #expect(model.isShuffled)
        #expect(commands.dispatch(KeyboardShortcut(.character("r"))) == "repeat")
        #expect(model.repeatMode == .all)
        #expect(commands.dispatch(KeyboardShortcut(.character("q"))) == "quit")
        #expect(coordinator.quitRequested)

        let escapeCoordinator = PlayerApplicationCoordinator()
        let escapeCommands = makePlayerCommands(model: model, coordinator: escapeCoordinator)
        #expect(escapeCommands.dispatch(KeyboardShortcut(.escape)) == "escape")
        #expect(escapeCoordinator.quitRequested)
    }

    @Test(
        "Responsive mode requires both width and height thresholds",
        arguments: [
            (CellSize(width: 40, height: 16), PlayerLayoutMode.minimum),
            (CellSize(width: 48, height: 18), .compact),
            (CellSize(width: 72, height: 24), .medium),
            (CellSize(width: 100, height: 27), .medium),
            (CellSize(width: 100, height: 28), .full),
        ]
    )
    func responsiveMode(size: CellSize, expected: PlayerLayoutMode) {
        #expect(PlayerLayoutMode.mode(for: size) == expected)
    }
}

extension TimeInstant {
    fileprivate static func seconds(_ value: Double) -> Self {
        .zero.advanced(by: .seconds(value))
    }
}
