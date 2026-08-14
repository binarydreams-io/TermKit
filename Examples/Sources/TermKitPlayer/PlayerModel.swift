import Observation
import TermKit

@MainActor
@Observable
final class PlayerModel {
  let tracks: [PlayerTrack]
  var currentTrackIndex = 0
  var selectedTrackIndex = 0
  var isPlaying = false
  var positionAtAnchor = TimeSpan.zero
  var playbackAnchor: TimeInstant?
  var volume = 0.65
  var isMuted = false
  var isShuffled = false
  var repeatMode = PlayerRepeatMode.off

  @ObservationIgnored
  let timeSource: any TimeSource

  init(tracks: [PlayerTrack] = PlayerModel.demoTracks, timeSource: any TimeSource) {
    precondition(tracks.isEmpty == false, "The player queue must contain a track.")
    self.tracks = tracks
    self.timeSource = timeSource
  }

  var currentTrack: PlayerTrack {
    tracks[currentTrackIndex]
  }

  var selectedTrack: PlayerTrack {
    tracks[selectedTrackIndex]
  }

  var volumeBinding: Binding<Double> {
    Binding(get: { self.volume }, set: { self.setVolume($0) })
  }

  func playbackProgressBinding(at instant: TimeInstant) -> Binding<Double> {
    Binding(get: { self.progress(at: instant) }, set: { self.setProgress($0) })
  }

  func position(at instant: TimeInstant) -> TimeSpan {
    guard isPlaying, let playbackAnchor else { return positionAtAnchor }
    return clampedPosition(positionAtAnchor + playbackAnchor.duration(to: instant))
  }

  func progress(at instant: TimeInstant) -> Double {
    guard currentTrack.duration > .zero else { return 0 }
    return position(at: instant).seconds / currentTrack.duration.seconds
  }

  func togglePlayback() {
    if isPlaying {
      pause()
    } else {
      play()
    }
  }

  func play() {
    guard isPlaying == false else { return }
    if positionAtAnchor >= currentTrack.duration {
      positionAtAnchor = .zero
    }
    playbackAnchor = timeSource.now
    isPlaying = true
  }

  func pause() {
    guard isPlaying else { return }
    positionAtAnchor = position(at: timeSource.now)
    playbackAnchor = nil
    isPlaying = false
  }

  func seek(by offset: TimeSpan) {
    let current = position(at: timeSource.now)
    positionAtAnchor = clampedPosition(current + offset)
    if isPlaying {
      playbackAnchor = timeSource.now
    }
  }

  func setProgress(_ value: Double) {
    guard value.isFinite else { return }
    let normalizedValue = min(1, max(0, value))
    positionAtAnchor = .seconds(currentTrack.duration.seconds * normalizedValue)
    if isPlaying {
      playbackAnchor = timeSource.now
    }
  }

  func nextTrack() {
    let next =
      isShuffled
        ? (currentTrackIndex + 2) % tracks.count
        : (currentTrackIndex + 1) % tracks.count
    selectTrack(at: next, startsPlaying: isPlaying)
  }

  func previousTrack() {
    let previous = (currentTrackIndex - 1 + tracks.count) % tracks.count
    selectTrack(at: previous, startsPlaying: isPlaying)
  }

  func moveSelection(by offset: Int) {
    selectedTrackIndex = min(tracks.count - 1, max(0, selectedTrackIndex + offset))
  }

  func playSelectedTrack() {
    selectTrack(at: selectedTrackIndex, startsPlaying: true)
  }

  func selectTrack(at index: Int, startsPlaying: Bool) {
    guard tracks.indices.contains(index) else { return }
    currentTrackIndex = index
    selectedTrackIndex = index
    positionAtAnchor = .zero
    isPlaying = startsPlaying
    playbackAnchor = startsPlaying ? timeSource.now : nil
  }

  func setVolume(_ value: Double) {
    guard value.isNaN == false else { return }
    volume = min(1, max(0, value))
    if volume > 0 {
      isMuted = false
    }
  }

  func changeVolume(by offset: Double) {
    setVolume(volume + offset)
  }

  func toggleMute() {
    isMuted.toggle()
  }

  func toggleShuffle() {
    isShuffled.toggle()
  }

  func cycleRepeatMode() {
    repeatMode.cycle()
  }

  private func clampedPosition(_ value: TimeSpan) -> TimeSpan {
    min(currentTrack.duration, max(.zero, value))
  }

  static let demoTracks = [
    PlayerTrack(
      id: "blue-hour",
      title: "Blue Hour Relay",
      artist: "North Circuit",
      album: "Signals After Rain",
      duration: .seconds(217),
      artwork: .png
    ),
    PlayerTrack(
      id: "glass-harbor",
      title: "Glass Harbor",
      artist: "Mira Vale",
      album: "Low Orbit Rooms",
      duration: .seconds(284),
      artwork: .jpeg
    ),
    PlayerTrack(
      id: "static-bloom",
      title: "Static Bloom",
      artist: "The Quiet Array",
      album: "Copper Skies",
      duration: .seconds(191),
      artwork: .png
    ),
    PlayerTrack(
      id: "last-carrier",
      title: "Last Carrier",
      artist: "Vela Memory",
      album: "Night Protocol",
      duration: .seconds(246),
      artwork: .jpeg
    )
  ]
}
