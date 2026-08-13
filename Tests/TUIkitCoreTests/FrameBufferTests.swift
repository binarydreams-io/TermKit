//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBufferTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing
@testable import TUIkitCore

@MainActor
@Suite("FrameBuffer Tests")
struct FrameBufferTests {
  @Test("Empty buffer has zero dimensions")
  func emptyBuffer() {
    let buffer = FrameBuffer()
    #expect(buffer.width == 0)
    #expect(buffer.height == 0)
    #expect(buffer.isEmpty)
  }

  @Test("Single line buffer has correct dimensions")
  func singleLine() {
    let buffer = FrameBuffer(text: "Hello")
    #expect(buffer.width == 5)
    #expect(buffer.height == 1)
    #expect(buffer.lines == ["Hello"])
  }

  @Test("Vertical append stacks lines")
  func verticalAppend() {
    var buffer = FrameBuffer(text: "Line 1")
    buffer.appendVertically(FrameBuffer(text: "Line 2"))
    #expect(buffer.height == 2)
    #expect(buffer.lines == ["Line 1", "Line 2"])
  }

  @Test("Vertical append with spacing")
  func verticalAppendWithSpacing() {
    var buffer = FrameBuffer(text: "Top")
    buffer.appendVertically(FrameBuffer(text: "Bottom"), spacing: 2)
    #expect(buffer.height == 4)
    #expect(buffer.lines == ["Top", "", "", "Bottom"])
  }

  @Test("Horizontal append places side by side")
  func horizontalAppend() {
    var buffer = FrameBuffer(text: "Left")
    buffer.appendHorizontally(FrameBuffer(text: "Right"), spacing: 1)
    #expect(buffer.height == 1)
    #expect(buffer.lines == ["Left Right"])
  }

  @Test("Horizontal append with different heights pads correctly")
  func horizontalAppendDifferentHeights() {
    var left = FrameBuffer(lines: ["AB", "CD"])
    let right = FrameBuffer(text: "X")
    left.appendHorizontally(right, spacing: 1)
    #expect(left.height == 2)
    #expect(left.lines[0] == "AB X")
    // Row 1: "CD" padded to width 2, spacing " ", no right content
    #expect(left.lines[1] == "CD ")
  }

  @Test("ANSI codes are excluded from width calculation")
  func ansiStrippedWidth() {
    let styled = "\u{1B}[1mBold\u{1B}[0m"
    let buffer = FrameBuffer(text: styled)
    #expect(buffer.width == 4) // "Bold" is 4 chars
  }

  @Test("Horizontal append with ANSI codes pads correctly")
  func horizontalAppendWithAnsi() {
    let styled = "\u{1B}[1mHi\u{1B}[0m"
    var left = FrameBuffer(text: styled)
    left.appendHorizontally(FrameBuffer(text: "There"), spacing: 1)
    #expect(left.height == 1)
    // "Hi" (styled) + " " (spacing) + "There"
    #expect(left.lines[0].stripped == "Hi There")
  }

  @Test("Vertical append translates interaction regions")
  func verticalAppendTranslatesRegions() {
    var top = FrameBuffer(
      text: "Top",
      regions: [InteractionRegion(id: "top", rect: TerminalCellRect(x: 0, y: 0, width: 3, height: 1))]
    )
    let bottom = FrameBuffer(
      text: "Bottom",
      regions: [InteractionRegion(id: "bottom", rect: TerminalCellRect(x: 1, y: 0, width: 4, height: 1))]
    )

    top.appendVertically(bottom, spacing: 2)

    #expect(top.regions == [
      InteractionRegion(id: "top", rect: TerminalCellRect(x: 0, y: 0, width: 3, height: 1)),
      InteractionRegion(id: "bottom", rect: TerminalCellRect(x: 1, y: 3, width: 4, height: 1))
    ])
  }

  @Test("Horizontal append uses terminal-cell offsets for regions")
  func horizontalAppendUsesTerminalCellGeometry() {
    var left = FrameBuffer(
      text: "界",
      regions: [InteractionRegion(id: "wide", rect: TerminalCellRect(x: 0, y: 0, width: 2, height: 1))]
    )
    let right = FrameBuffer(
      text: "X",
      regions: [InteractionRegion(id: "right", rect: TerminalCellRect(x: 0, y: 0, width: 1, height: 1))]
    )

    left.appendHorizontally(right, spacing: 1)

    #expect(left.width == 4)
    #expect(left.regions[1].rect == TerminalCellRect(x: 3, y: 0, width: 1, height: 1))
  }

  @Test("Clipping translates and reduces interaction regions")
  func clippingRegions() {
    let buffer = FrameBuffer(
      lines: ["ABCDE", "FGHIJ", "KLMNO"],
      regions: [
        InteractionRegion(id: "partial", rect: TerminalCellRect(x: 2, y: 1, width: 3, height: 2)),
        InteractionRegion(id: "outside", rect: TerminalCellRect(x: 0, y: 2, width: 1, height: 1))
      ]
    )

    let clipped = buffer.clipped(to: TerminalCellRect(x: 3, y: 0, width: 2, height: 2))

    #expect(clipped.lines == ["DE", "IJ"])
    #expect(clipped.regions == [
      InteractionRegion(id: "partial", rect: TerminalCellRect(x: 0, y: 1, width: 2, height: 1))
    ])
  }

  @Test("Modal-style compositing keeps top regions last")
  func compositingPreservesRegionOrder() {
    let base = FrameBuffer(
      lines: ["........", "........", "........"],
      regions: [InteractionRegion(id: "base", rect: TerminalCellRect(x: 0, y: 0, width: 8, height: 3))]
    )
    let modal = FrameBuffer(
      lines: ["MODL", "----"],
      regions: [InteractionRegion(id: "modal", rect: TerminalCellRect(x: 0, y: 0, width: 4, height: 2))]
    )

    let composited = base.composited(with: modal, at: (x: 2, y: 1))

    #expect(composited.regions == [
      InteractionRegion(id: "base", rect: TerminalCellRect(x: 0, y: 0, width: 8, height: 3)),
      InteractionRegion(id: "modal", rect: TerminalCellRect(x: 2, y: 1, width: 4, height: 2))
    ])
    #expect(composited.regions.last?.id == "modal")
  }

  @Test("Line overlay keeps deterministic region order")
  func overlayPreservesRegionOrder() {
    var base = FrameBuffer(
      text: "Base",
      regions: [InteractionRegion(id: "base", rect: TerminalCellRect(x: 0, y: 0, width: 4, height: 1))]
    )
    let overlay = FrameBuffer(
      text: "Top",
      regions: [InteractionRegion(id: "top", rect: TerminalCellRect(x: 0, y: 0, width: 3, height: 1))]
    )

    base.overlay(overlay)

    #expect(base.regions.map(\.id) == ["base", "top"])
  }
}
