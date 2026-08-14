import TermKit

struct PlayerView: View {
    let model: PlayerModel
    let artwork: PlayerArtwork

    @Environment(TerminalSizeEnvironmentKey.self) private var terminalSize

    var graphBody: [NodeDescriptor] {
        let mode = PlayerLayoutMode.mode(for: terminalSize)
        if model.isPlaying {
            TimelineView(.animation(minimumInterval: .milliseconds(80))) { context in
                PlayerDeck(model: model, artwork: artwork, mode: mode, size: terminalSize, instant: context.instant)
            }
        } else {
            PlayerDeck(
                model: model,
                artwork: artwork,
                mode: mode,
                size: terminalSize,
                instant: model.timeSource.now
            )
        }
    }
}

private struct PlayerDeck: View {
    let model: PlayerModel
    let artwork: PlayerArtwork
    let mode: PlayerLayoutMode
    let size: CellSize
    let instant: TimeInstant

    var graphBody: [NodeDescriptor] {
        switch mode {
        case .full:
            fullLayout.graphBody
        case .medium:
            mediumLayout.graphBody
        case .compact:
            compactLayout.graphBody
        case .minimum:
            minimumLayout.graphBody
        }
    }

    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 1) {
            header("FULL DECK // TK-97")
            HStack(alignment: .top, spacing: 2) {
                albumArt(width: 24, height: 10)
                deck(width: max(60, size.width - 28), includesSpectrum: true, includesAlbum: true)
            }
            queue(rows: min(7, max(3, size.height - 20)))
            footer
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 1) {
            header("REDUCED DECK // TK-97")
            HStack(alignment: .top, spacing: 2) {
                albumArt(width: 16, height: 7)
                deck(width: max(50, size.width - 20), includesSpectrum: true, includesAlbum: false)
            }
            queue(rows: 4)
            footer
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 1) {
            header("COMPACT DECK // TK-97")
            deck(width: size.width, includesSpectrum: false, includesAlbum: false)
            queue(rows: max(2, min(5, size.height - 11)))
            footer
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var minimumLayout: some View {
        VStack(alignment: .leading) {
            header("TERMKIT PLAYER")
            Text(model.currentTrack.title, id: "minimum-track", style: PlayerStyles.heading)
            Text(statusLine, id: "minimum-state", style: PlayerStyles.data)
            Text("Terminal too small for deck view", id: "minimum-message", style: PlayerStyles.quiet)
            Text("Space play/pause · q quit", id: "minimum-shortcuts", style: PlayerStyles.body)
            Text("visual simulation · no audio output", id: "minimum-silent", style: PlayerStyles.quiet)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func header(_ title: String) -> some View {
        SurfaceView(
            text: title,
            foreground: PlayerStyles.amber,
            background: PlayerStyles.steel,
            id: "player-header",
            elevation: .raised
        )
        .frame(width: size.width, height: 1, alignment: .topLeading)
    }

    private func albumArt(width: Int, height: Int) -> some View {
        Image(
            artwork.image(for: model.currentTrack.artwork),
            id: "album-art",
            label: "Original artwork for \(model.currentTrack.album)",
            contentMode: .fill,
            background: RGBA8(red: 15, green: 39, blue: 61)
        )
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func deck(width: Int, includesSpectrum: Bool, includesAlbum: Bool) -> some View {
        VStack(alignment: .leading) {
            SurfaceView(
                text: trackMetadata(includesAlbum: includesAlbum),
                foreground: PlayerStyles.amber,
                background: PlayerStyles.panel,
                id: "track-display",
                padding: EdgeInsets(top: 1, leading: 1, bottom: 0, trailing: 1),
                elevation: .raised
            )
            .frame(width: width, height: 3, alignment: .topLeading)
            Text(statusLine, id: "playback-state", style: PlayerStyles.data)
            ProgressBar(
                value: model.playbackProgressBinding(at: instant),
                id: "playback-progress",
                label: "Playback position",
                adjustmentStep: 5 / model.currentTrack.duration.seconds,
                filledStyle: PlayerStyles.data,
                emptyStyle: PlayerStyles.quiet
            )
            .frame(width: width, height: 1, alignment: .topLeading)
            HStack(spacing: 1) {
                Button("[|<]", id: "previous-track", style: PlayerStyles.transport) { model.previousTrack() }
                Button(model.isPlaying ? "[||]" : "[▶]", id: "play-pause", style: PlayerStyles.transport) {
                    model.togglePlayback()
                }
                Button("[>|]", id: "next-track", style: PlayerStyles.transport) { model.nextTrack() }
                Text(volumeLine, id: "volume-state", style: PlayerStyles.body)
                ProgressBar(
                    value: model.volumeBinding,
                    id: "volume-progress",
                    label: "Volume",
                    adjustmentStep: 0.05,
                    filledStyle: PlayerStyles.data,
                    emptyStyle: PlayerStyles.quiet
                )
                .frame(width: 10, height: 1, alignment: .topLeading)
                Text(modeLine, id: "play-mode", style: PlayerStyles.quiet)
            }
            if includesSpectrum {
                SpectrumView(instant: instant, isActive: model.isPlaying)
                    .frame(width: width, height: 1, alignment: .topLeading)
            }
        }
        .frame(width: width, height: includesSpectrum ? 9 : 7, alignment: .topLeading)
    }

    private func queue(rows: Int) -> some View {
        VStack(alignment: .leading) {
            Text("QUEUE", id: "queue-heading", style: PlayerStyles.heading)
            PlayerQueueView(model: model, visibleRowCount: rows)
                .frame(width: size.width, height: rows, alignment: .topLeading)
        }
    }

    private var footer: some View {
        Text(
            "Visual simulation, no audio output · Space play · n/p track · ←/→ seek · +/- volume · m mute · s shuffle · r repeat · q quit",
            id: "keyboard-hints",
            style: PlayerStyles.quiet
        )
        .frame(width: size.width, height: 1, alignment: .topLeading)
    }

    private var statusLine: String {
        let state = model.isPlaying ? "PLAYING" : "PAUSED"
        return "\(state)  \(formatTime(model.position(at: instant))) / \(formatTime(model.currentTrack.duration))"
    }

    private func trackMetadata(includesAlbum: Bool) -> String {
        let track = model.currentTrack
        return includesAlbum ? "\(track.title)\n\(track.artist) · \(track.album)" : "\(track.title)\n\(track.artist)"
    }

    private var volumeLine: String {
        model.isMuted ? "VOL MUTED" : "VOL \(Int((model.volume * 100).rounded()))%"
    }

    private var modeLine: String {
        "SHUF \(model.isShuffled ? "ON" : "OFF") · REP \(model.repeatMode.rawValue.uppercased())"
    }
}
