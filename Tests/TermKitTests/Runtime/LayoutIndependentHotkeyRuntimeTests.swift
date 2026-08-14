@testable import TermKit
import Testing

@MainActor
struct LayoutIndependentHotkeyRuntimeTests {
  @Test
  func `Runtime dispatches a Latin command from a Cyrillic key`() throws {
    var invocationCount = 0
    let runtime = Runtime(
      view: Text("Hotkeys"),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 10, height: 1),
      timeSource: DeterministicTimeSource(),
      commands: KeyboardCommandSet([
        KeyboardCommand(
          id: "save",
          title: "Save",
          shortcut: KeyboardShortcut(.character("s"))
        ) {
          invocationCount += 1
        }
      ])
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(.input(.key(TerminalKeyEvent(key: .text("ы")))))

    #expect(invocationCount == 1)
  }

  @Test
  func `Runtime uses a Kitty shifted key for shortcut matching`() throws {
    var invocationCount = 0
    let runtime = Runtime(
      view: Text("Hotkeys"),
      presenter: FramePresenter(session: FakeTerminalSession()),
      terminalSize: CellSize(width: 10, height: 1),
      timeSource: DeterministicTimeSource(),
      commands: KeyboardCommandSet([
        KeyboardCommand(
          id: "increase",
          title: "Increase",
          shortcut: KeyboardShortcut(.character("+"), modifiers: .shift)
        ) {
          invocationCount += 1
        }
      ])
    )
    try runtime.start()
    _ = try runtime.renderIfDue(at: .zero)

    try runtime.process(
      .input(
        .key(
          TerminalKeyEvent(
            key: .text("="),
            modifiers: .shift,
            shiftedKey: "+"
          )
        )
      )
    )

    #expect(invocationCount == 1)
  }
}
