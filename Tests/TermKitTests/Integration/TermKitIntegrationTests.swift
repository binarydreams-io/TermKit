import TermKit
import Testing

@MainActor
struct TermKitIntegrationTests {
  private enum Root {}

  @Test
  func `Umbrella product exposes declarative views and animations`() {
    let descriptor = NodeDescriptor(type: Root.self)
    let animation = Animation.easeInOut(duration: .milliseconds(150))
    let view = DescriptorView(descriptor)

    #expect(view.graphBody.count == 1)
    #expect(view.graphBody.first?.identity == descriptor.identity)
    #expect(animation.duration == .milliseconds(150))
    #expect(TermKitRelease.version == "2.2.3")
  }

  @Test
  func `Generic runtime view initializer is public`() {
    let session = CompileOnlyRuntimeSession()
    _ = Runtime(
      view: Text("Root"),
      presenter: FramePresenter(session: session),
      terminalSize: CellSize(width: 10, height: 2)
    )
  }

  @Test
  func `Reduced motion exposes a static activity indicator`() {
    let indicator = ActivityIndicator(sample: TimelineSample(instant: .zero, reduceMotion: true))
    #expect(indicator.schedule == nil)
    #expect(indicator.text == "...")
  }

  @Test
  func `Umbrella product composes a bound agent prompt with accessories`() {
    final class Model {
      var document = PromptDocument(text: "Compose")
    }

    let model = Model()
    let prompt = AgentPrompt<String>(
      Binding(get: { model.document }, set: { model.document = $0 }),
      actions: AgentPromptActions(submit: { _ in }, cancel: {}, paste: { _ in }, attach: { _ in }),
      leadingAccessory: { Text("L") },
      trailingAccessory: { Text("T") }
    )

    #expect(prompt.graphBody.first?.children.count == 3)
  }

  @Test
  func `Public documentation examples compile`() {
    #expect(DocumentationCounterView().graphBody.count == 1)
    #expect(DocumentationStatusView(message: "Ready").graphBody.count == 1)
    #expect(DocumentationPromptView().graphBody.count == 1)

    _ = Text("Saving")
      .foregroundColor(.white)
      .opacity(0.8)
      .offset(x: 2, y: 0)
      .animation(.easeInOut(duration: .milliseconds(180)), value: true)
  }
}

@MainActor
private struct DocumentationCounterView: View {
  @State private var count = 0

  var graphBody: [NodeDescriptor] {
    VStack(alignment: .leading, spacing: 1) {
      Text("Count: \(count)")
      Button("Increment") { count += 1 }
    }
    .padding(1)
    .graphBody
  }
}

@MainActor
private struct DocumentationStatusView: View {
  let message: String

  var graphBody: [NodeDescriptor] {
    VStack(alignment: .leading, spacing: 1) {
      Text("Build")
      Text(message)
    }
    .padding(1)
    .frame(width: 40, alignment: .topLeading)
    .graphBody
  }
}

@MainActor
private struct DocumentationPromptView: View {
  @State private var document = PromptDocument()

  var graphBody: [NodeDescriptor] {
    AgentPrompt<String>(
      $document,
      actions: AgentPromptActions(
        submit: { _ in },
        cancel: {},
        paste: { _ in },
        attach: { _ in }
      ),
      leadingAccessory: { Text(">") },
      trailingAccessory: { Text("Enter to send") }
    ).graphBody
  }
}

private final class CompileOnlyRuntimeSession: RuntimeTerminalSession {
  let capabilities = TerminalCapabilities(color: .ansi16, synchronizedOutput: .unsupported)
  private(set) var state: TerminalSessionState = .inactive

  func start() throws -> TerminalSessionTransition {
    state = .active
    return .started
  }

  func suspend() throws -> TerminalSessionTransition {
    state = .suspended
    return .suspended
  }

  func resume() throws -> TerminalSessionTransition {
    state = .active
    return .resumed(requiresFullRepaint: true)
  }

  func stop() throws -> TerminalSessionTransition {
    state = .inactive
    return .stopped
  }

  func present(_ bytes: [UInt8]) throws {}
  func handleSignalEvent(_ event: TerminalSignalEvent) throws -> TerminalSignalAction {
    .terminate
  }

  func readInput(maximumByteCount: Int) throws -> [UInt8] {
    []
  }

  func readTerminalSize() throws -> TerminalSize {
    TerminalSize(columns: 10, rows: 2)
  }
}
