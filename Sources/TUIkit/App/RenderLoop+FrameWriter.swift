//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderLoop+FrameWriter.swift
//
//  Created by LAYERED.work
//  License: MIT

/// ANSI background codes for each render surface in a frame.
///
/// Keeping these grouped avoids accidentally rendering every surface
/// with `palette.background` and ignoring palette-specific tokens like
/// `statusBarBackground`.
struct RenderBackgroundCodes: Equatable {
  /// Main content area background code.
  let content: String

  /// App header background code.
  let appHeader: String

  /// Status bar background code.
  let statusBar: String

  init(palette: any Palette) {
    self.content = ANSIRenderer.backgroundCode(for: palette.background)
    self.appHeader = ANSIRenderer.backgroundCode(for: palette.appHeaderBackground)
    self.statusBar = ANSIRenderer.backgroundCode(for: palette.statusBarBackground)
  }
}

@MainActor
final class RenderFrameWriter {
  private let terminal: any TerminalProtocol
  private let statusBar: StatusBarState
  private let appHeader: AppHeaderState
  private let diffWriter = FrameDiffWriter()

  init(
    terminal: any TerminalProtocol,
    statusBar: StatusBarState,
    appHeader: AppHeaderState
  ) {
    self.terminal = terminal
    self.statusBar = statusBar
    self.appHeader = appHeader
  }

  func invalidate() {
    diffWriter.invalidate()
  }

  /// Writes the assembled frame to the terminal using diff-based output.
  ///
  /// Builds terminal-ready output lines, then writes app header, content,
  /// and status bar inside a single buffered frame (normally one syscall).
  func writeFrame(
    buffer: FrameBuffer,
    environment: EnvironmentValues,
    terminalWidth: Int,
    terminalHeight: Int,
    statusBarHeight: Int,
    headerHeight: Int
  ) {
    let backgroundCodes = RenderBackgroundCodes(palette: environment.palette)
    let reset = ANSIRenderer.reset
    let contentHeight = terminalHeight - statusBarHeight - headerHeight

    let outputLines = diffWriter.buildOutputLines(
      buffer: buffer,
      terminalWidth: terminalWidth,
      terminalHeight: contentHeight,
      bgCode: backgroundCodes.content,
      reset: reset
    )

    terminal.beginFrame()

    if appHeader.hasContent {
      renderAppHeader(
        atRow: 1,
        terminalWidth: terminalWidth,
        environment: environment,
        bgCode: backgroundCodes.appHeader,
        reset: reset
      )
    }

    diffWriter.writeContentDiff(
      newLines: outputLines,
      terminal: terminal,
      startRow: 1 + headerHeight
    )

    if statusBar.hasItems {
      renderStatusBar(
        atRow: terminalHeight - statusBarHeight + 1,
        terminalWidth: terminalWidth,
        environment: environment,
        bgCode: backgroundCodes.statusBar,
        reset: reset
      )
    }

    terminal.endFrame()
  }

  /// Renders the app header at the specified terminal row.
  private func renderAppHeader(
    atRow row: Int,
    terminalWidth: Int,
    environment: EnvironmentValues,
    bgCode: String,
    reset: String
  ) {
    guard let contentBuffer = appHeader.contentBuffer else { return }

    let headerView = AppHeader(contentBuffer: contentBuffer)

    let context = RenderContext(
      availableWidth: terminalWidth,
      availableHeight: appHeader.height,
      environment: environment
    )

    let buffer = renderToBuffer(headerView, context: context)

    let outputLines = diffWriter.buildOutputLines(
      buffer: buffer,
      terminalWidth: terminalWidth,
      terminalHeight: buffer.height,
      bgCode: bgCode,
      reset: reset
    )
    diffWriter.writeAppHeaderDiff(newLines: outputLines, terminal: terminal, startRow: row)
  }

  /// Renders the status bar at the specified terminal row.
  private func renderStatusBar(
    atRow row: Int,
    terminalWidth: Int,
    environment: EnvironmentValues,
    bgCode: String,
    reset: String
  ) {
    let palette = environment.palette

    let highlightColor =
      statusBar.highlightColor == .cyan
        ? palette.accent
        : statusBar.highlightColor
    let labelColor = statusBar.labelColor ?? palette.foreground

    let statusBarView = StatusBar(
      userItems: statusBar.currentUserItems,
      systemItems: statusBar.currentSystemItems,
      style: statusBar.style,
      alignment: statusBar.alignment,
      highlightColor: highlightColor,
      labelColor: labelColor
    )

    let context = RenderContext(
      availableWidth: terminalWidth,
      availableHeight: statusBarView.height,
      environment: environment
    )

    let buffer = renderToBuffer(statusBarView, context: context)

    let outputLines = diffWriter.buildOutputLines(
      buffer: buffer,
      terminalWidth: terminalWidth,
      terminalHeight: buffer.height,
      bgCode: bgCode,
      reset: reset
    )
    diffWriter.writeStatusBarDiff(newLines: outputLines, terminal: terminal, startRow: row)
  }
}
