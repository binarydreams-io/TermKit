//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StringTerminalWidthANSITests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing
@testable import TUIkitCore

@MainActor
@Suite("String+TerminalWidth+ANSI Tests")
struct StringTerminalWidthANSITests {
  // MARK: - ansiAwarePrefix trailing escape preservation

  @Test("Prefix at exact visible width keeps a trailing reset")
  func prefixExactWidthKeepsTrailingReset() {
    let styled = "\u{1B}[31mHi\u{1B}[0m"
    #expect(styled.ansiAwarePrefix(visibleCount: 2) == styled)
  }

  @Test("Prefix cut mid-way still emits escapes that occur after the cut")
  func prefixMidCutEmitsTrailingEscapes() {
    let styled = "\u{1B}[31mab\u{1B}[0mcd"
    #expect(styled.ansiAwarePrefix(visibleCount: 1) == "\u{1B}[31ma\u{1B}[0m")
  }

  @Test("Prefix drains multiple trailing escape sequences after the cut")
  func prefixDrainsMultipleTrailingEscapes() {
    let styled = "\u{1B}[31ma\u{1B}[1mb\u{1B}[0m\u{1B}[39mc"
    #expect(styled.ansiAwarePrefix(visibleCount: 1) == "\u{1B}[31ma\u{1B}[1m\u{1B}[0m\u{1B}[39m")
  }

  // MARK: - ansiAwarePrefix unaffected behavior

  @Test("Prefix of plain ASCII text is unchanged by the fix")
  func prefixPlainASCIIUnchanged() {
    let plain = "Hello World"
    #expect(plain.ansiAwarePrefix(visibleCount: 5) == "Hello")
  }

  @Test("Prefix with budget larger than the string returns it whole")
  func prefixBudgetLargerThanStringReturnsWhole() {
    let styled = "\u{1B}[31mHi\u{1B}[0m"
    #expect(styled.ansiAwarePrefix(visibleCount: 100) == styled)
  }

  @Test("Prefix with zero budget returns an empty string")
  func prefixZeroBudgetReturnsEmpty() {
    let styled = "\u{1B}[31mHi\u{1B}[0m"
    #expect(styled.ansiAwarePrefix(visibleCount: 0) == "")
  }

  // MARK: - CSI sequences beyond the SGR shape

  @Test("A private-mode sequence occupies no cell")
  func privateModeSequenceOccupiesNoCell() {
    let hidden = "\u{1B}[?25lab\u{1B}[?25h"
    #expect(hidden.strippedLength == 2)
    #expect(hidden.stripped == "ab")
  }

  @Test("A sequence whose final byte is a symbol occupies no cell")
  func symbolFinalByteOccupiesNoCell() {
    #expect("\u{1B}[2~ab".strippedLength == 2)
    #expect("\u{1B}[2~ab".stripped == "ab")
  }

  @Test("A prefix keeps a private-mode sequence and spends no budget on it")
  func prefixKeepsPrivateModeSequence() {
    #expect("\u{1B}[?25lab".ansiAwarePrefix(visibleCount: 1) == "\u{1B}[?25la")
  }

  @Test("A suffix drops the cells after a private-mode sequence")
  func suffixSkipsPrivateModeSequence() {
    #expect("\u{1B}[?25lab".ansiAwareSuffix(droppingVisible: 1) == "b")
  }

  @Test("The leading sequences include a private-mode sequence")
  func leadingSequencesIncludePrivateMode() {
    #expect("\u{1B}[?25l\u{1B}[31mab".leadingANSISequences() == "\u{1B}[?25l\u{1B}[31m")
  }
}
