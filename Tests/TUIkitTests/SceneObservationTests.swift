//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneObservationTests.swift
//
//  License: MIT

import Observation
import Testing
@testable import TUIkit
import TUIkitTestSupport

@Observable
private final class ShellModel {
  var showsDetail = false
}

/// An app whose `WindowGroup` content closure reads an observable model —
/// the shape of a root screen switch in an application shell. The model is
/// static because `App` requires an argument-free `init`, the way a real
/// shell hands its environment in through a static context.
private struct ShellApp: App {
  @MainActor static var model = ShellModel()

  var body: some Scene {
    WindowGroup {
      if Self.model.showsDetail {
        Text("Detail")
      } else {
        Text("Root")
      }
    }
  }
}

@MainActor
@Suite("Scene Observation Tests", .serialized)
struct SceneObservationTests {
  @Test("a model read in the scene content re-renders when it changes")
  func sceneContentReadTriggersRender() {
    let tuiContext = TUIContext()
    ShellApp.model = ShellModel()
    let renderer = RenderSceneRenderer(
      app: ShellApp(),
      terminal: MockTerminal(),
      statusBar: tuiContext.statusBar,
      appHeader: tuiContext.appHeader,
      focusManager: tuiContext.focusManager,
      tuiContext: tuiContext
    )

    renderer.render(pulsePhase: 0, cursorTimer: nil)
    tuiContext.appState.didRender()
    #expect(!tuiContext.appState.needsRender)

    ShellApp.model.showsDetail = true

    #expect(tuiContext.appState.needsRender)
  }
}
