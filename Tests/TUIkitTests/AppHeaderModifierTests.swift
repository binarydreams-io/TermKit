import Testing
@testable import TUIkit

@MainActor
@Suite("AppHeaderModifier Tests")
struct AppHeaderModifierTests {
  @Test("Header and content use distinct interaction identities")
  func distinctInteractionIdentities() throws {
    let tuiContext = TUIContext()
    tuiContext.beginRenderPass()
    let context = RenderContext(
      availableWidth: 40,
      availableHeight: 10,
      tuiContext: tuiContext,
      identity: ViewIdentity(path: "app-header")
    )
    let view = Button("Content") {}
      .appHeader {
        Button("Header") {}
      }

    let contentBuffer = renderToBuffer(view, context: context)
    let headerBuffer = try #require(tuiContext.appHeader.contentBuffer)
    let contentID = try #require(contentBuffer.regions.first?.id)
    let headerID = try #require(headerBuffer.regions.first?.id)

    #expect(contentID != headerID)
  }
}
