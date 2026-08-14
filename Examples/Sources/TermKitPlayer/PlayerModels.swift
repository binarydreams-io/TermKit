import TermKit

struct PlayerTrack: Identifiable, Sendable, Hashable {
  let id: String
  let title: String
  let artist: String
  let album: String
  let duration: TimeSpan
  let artwork: ArtworkKind
}

enum ArtworkKind: Sendable, Hashable {
  case png
  case jpeg
}

enum PlayerRepeatMode: String, Sendable, CaseIterable {
  case off
  case all
  case one

  mutating func cycle() {
    self =
      switch self {
      case .off: .all
      case .all: .one
      case .one: .off
      }
  }
}

enum PlayerLayoutMode: String, Sendable {
  case full
  case medium
  case compact
  case minimum

  static func mode(for size: CellSize) -> Self {
    if size.width >= 100, size.height >= 28 {
      return .full
    }
    if size.width >= 72, size.height >= 24 {
      return .medium
    }
    if size.width >= 48, size.height >= 18 {
      return .compact
    }
    return .minimum
  }
}

struct PlayerArtwork: Sendable {
  let png: RasterImage
  let jpeg: RasterImage

  func image(for kind: ArtworkKind) -> RasterImage {
    switch kind {
    case .png: png
    case .jpeg: jpeg
    }
  }
}
