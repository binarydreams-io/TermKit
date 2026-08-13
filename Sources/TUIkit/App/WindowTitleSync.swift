//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WindowTitleSync.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Window Title Synchronization

/// Collects the declared window title of one frame and writes it once.
///
/// `PreferenceStorage.beginRenderPass()` drops every callback at the start
/// of a frame, so the observer is registered again per frame. The collected
/// title is written only when it differs from the last written one: a
/// static screen therefore emits no OSC sequences after its first frame.
///
/// A frame that declares no title leaves the current one in place. The
/// runtime pushes the terminal's own title at startup and pops it in
/// `cleanup()`, so nothing set here survives the process.
final class WindowTitleSync {
  /// The title declared during the current frame.
  private var pendingTitle: String?

  /// The title last written to the terminal.
  private var writtenTitle: String?

  /// Creates a synchronizer that has written no title yet.
  init() {}

  /// Starts observing the window title preference for a new frame.
  ///
  /// - Parameter preferences: The storage collecting this frame's preferences.
  func beginFrame(preferences: PreferenceStorage) {
    pendingTitle = nil
    preferences.onPreferenceChange(TerminalTitleKey.self) { [weak self] title in
      guard let title else { return }
      self?.pendingTitle = title
    }
  }

  /// Writes the collected title unless it repeats the last written value.
  ///
  /// - Parameter terminal: The terminal receiving the title.
  @MainActor
  func commit(to terminal: any TerminalProtocol) {
    guard let pendingTitle, pendingTitle != writtenTitle else { return }
    writtenTitle = pendingTitle
    terminal.setWindowTitle(pendingTitle)
  }
}
