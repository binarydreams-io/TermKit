//  TUIkit - Terminal UI Kit for Swift
//  InputEventTests.swift
//
//  License: MIT

import Testing
@testable import TUIkitCore

@Suite("Terminal Input Parser Tests")
struct TerminalInputParserTests {
  @Test(
    "Parses SGR mouse actions",
    arguments: [
      MouseParseCase(sequence: "\u{1B}[<0;10;20M", action: .press(.left)),
      MouseParseCase(sequence: "\u{1B}[<2;10;20m", action: .release(.right)),
      MouseParseCase(sequence: "\u{1B}[<33;10;20M", action: .drag(.middle)),
      MouseParseCase(sequence: "\u{1B}[<35;10;20M", action: .move),
      MouseParseCase(sequence: "\u{1B}[<64;10;20M", action: .scroll(.up)),
      MouseParseCase(sequence: "\u{1B}[<65;10;20M", action: .scroll(.down))
    ]
  )
  func parsesMouseActions(parseCase: MouseParseCase) {
    var parser = TerminalInputParser()
    parser.append(Array(parseCase.sequence.utf8))

    #expect(
      parser.nextEvent()
        == .mouse(MouseEvent(action: parseCase.action, column: 9, row: 19))
    )
  }

  @Test("Parses SGR mouse modifiers")
  func parsesMouseModifiers() {
    var parser = TerminalInputParser()
    parser.append(Array("\u{1B}[<28;1;1M".utf8))

    #expect(
      parser.nextEvent()
        == .mouse(
          MouseEvent(
            action: .press(.left),
            column: 0,
            row: 0,
            ctrl: true,
            alt: true,
            shift: true
          )
        )
    )
  }

  @Test("Preserves a partial SGR sequence")
  func preservesPartialMouseSequence() {
    var parser = TerminalInputParser()
    parser.append([0x1B])

    #expect(parser.nextEvent() == nil)

    parser.append(Array("[<0;12".utf8))

    #expect(parser.nextEvent() == nil)

    parser.append(Array(";34M".utf8))
    #expect(
      parser.nextEvent()
        == .mouse(MouseEvent(action: .press(.left), column: 11, row: 33))
    )
  }

  @Test("Emits multiple keyboard, mouse, and paste events")
  func emitsMultipleInputEvents() {
    var parser = TerminalInputParser()
    parser.append(Array("a\u{1B}[<0;2;3M\u{1B}[A\u{1B}[200~hello\u{1B}[201~b".utf8))

    var events: [InputEvent] = []
    while let event = parser.nextEvent() {
      events.append(event)
    }

    #expect(
      events == [
        .key(KeyEvent(character: "a")),
        .mouse(MouseEvent(action: .press(.left), column: 1, row: 2)),
        .key(KeyEvent(key: .up)),
        .key(KeyEvent(key: .paste("hello"))),
        .key(KeyEvent(character: "b"))
      ]
    )
  }

  @Test("Preserves partial bracketed paste content")
  func preservesPartialPaste() {
    var parser = TerminalInputParser()
    parser.append(Array("\u{1B}[200~part".utf8))

    #expect(parser.nextEvent() == nil)

    parser.append(Array("ial\u{1B}[201~x".utf8))
    #expect(parser.nextEvent() == .key(KeyEvent(key: .paste("partial"))))
    #expect(parser.nextEvent() == .key(KeyEvent(character: "x")))
  }

  @Test("Accepts a fragmented paste at the byte limit", .timeLimit(.minutes(1)))
  func acceptsFragmentedPasteAtLimit() {
    var parser = TerminalInputParser()
    parser.append(Array("\u{1B}[200~".utf8))

    for _ in 0 ..< 65536 {
      parser.append([0x61])
      _ = parser.nextEvent()
    }

    parser.append(Array("\u{1B}[201~".utf8))
    let event = parser.nextEvent()
    guard case let .key(keyEvent) = event,
          case let .paste(text) = keyEvent.key
    else {
      Issue.record("Expected a paste event")
      return
    }
    #expect(text.utf8.count == 65536)
  }

  @Test("Discards oversized paste content and recovers")
  func oversizedPasteRecovers() {
    var parser = TerminalInputParser()
    parser.append(Array("\u{1B}[200~".utf8) + [UInt8](repeating: 0x61, count: 65537))

    #expect(parser.nextEvent() == nil)

    parser.append(Array("ignored\u{1B}[201~x".utf8))
    #expect(parser.nextEvent() == .key(KeyEvent(character: "x")))
  }

  @Test("Discards an oversized CSI sequence and recovers")
  func oversizedCSISequenceRecovers() {
    var parser = TerminalInputParser()
    parser.append([0x1B, 0x5B] + [UInt8](repeating: 0x30, count: 65534))

    #expect(parser.nextEvent() == nil)

    parser.append(Array("x".utf8))
    #expect(parser.nextEvent() == .key(KeyEvent(character: "x")))
  }

  @Test("Input models are Sendable and Equatable")
  func inputModelsAreSendableAndEquatable() {
    let mouse = MouseEvent(action: .move, column: 3, row: 4)
    let event = InputEvent.mouse(mouse)

    requireSendable(mouse)
    requireSendable(event)
    #expect(event == .mouse(mouse))
  }
}

struct MouseParseCase: Sendable {
  let sequence: String
  let action: MouseEvent.Action
}

private func requireSendable(_: some Sendable) {}
