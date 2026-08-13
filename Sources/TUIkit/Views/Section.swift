//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Section.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Section

/// A container view that groups content with optional header and footer.
///
/// `Section` organizes list content into logical groups with visual headers
/// and footers. When used inside a `List`, sections provide hierarchical
/// structure with appropriate styling.
///
/// ## SwiftUI Conformity
///
/// This implementation matches the SwiftUI `Section` API:
/// - `Section { content } header: { header } footer: { footer }`
/// - `Section("Title") { content }`
///
/// ## Usage
///
/// ```swift
/// List(selection: $selection) {
///     Section {
///         ForEach(recentItems) { item in
///             Text(item.name)
///         }
///     } header: {
///         Text("Recent")
///     }
///
///     Section("All Items") {
///         ForEach(allItems) { item in
///             Text(item.name)
///         }
///     }
/// }
/// ```
///
/// ## Visual Rendering
///
/// - **Header**: Rendered with dimmed foreground and bold styling
/// - **Footer**: Rendered with dimmed foreground
/// - **Content**: Rendered normally between header and footer
/// - **Spacing**: Sections are separated by vertical space in List
public struct Section<Parent: View, Content: View, Footer: View>: View {
  /// The header view displayed above the section content.
  let header: Parent

  /// The main content of the section.
  let content: Content

  /// The footer view displayed below the section content.
  let footer: Footer

  public var body: some View {
    _SectionCore(header: header, content: content, footer: footer)
  }
}

// MARK: - Full Initializer (header + content + footer)

extension Section {
  /// Creates a section with content, header, and footer.
  ///
  /// This is the most flexible initializer, matching SwiftUI's signature.
  ///
  /// - Parameters:
  ///   - content: A ViewBuilder that defines the section's main content.
  ///   - header: A ViewBuilder that defines the header view.
  ///   - footer: A ViewBuilder that defines the footer view.
  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Parent,
    @ViewBuilder footer: () -> Footer
  ) {
    self.content = content()
    self.header = header()
    self.footer = footer()
  }
}

// MARK: - Header + Content (no footer)

extension Section where Footer == EmptyView {
  /// Creates a section with content and header, without a footer.
  ///
  /// - Parameters:
  ///   - content: A ViewBuilder that defines the section's main content.
  ///   - header: A ViewBuilder that defines the header view.
  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Parent
  ) {
    self.content = content()
    self.header = header()
    self.footer = EmptyView()
  }
}

// MARK: - Content + Footer (no header)

extension Section where Parent == EmptyView {
  /// Creates a section with content and footer, without a header.
  ///
  /// - Parameters:
  ///   - content: A ViewBuilder that defines the section's main content.
  ///   - footer: A ViewBuilder that defines the footer view.
  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.content = content()
    self.header = EmptyView()
    self.footer = footer()
  }
}

// MARK: - Content Only (no header, no footer)

extension Section where Parent == EmptyView, Footer == EmptyView {
  /// Creates a section with content only, without header or footer.
  ///
  /// - Parameter content: A ViewBuilder that defines the section's main content.
  public init(
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
    self.header = EmptyView()
    self.footer = EmptyView()
  }
}

// MARK: - String Title Convenience

extension Section where Parent == Text, Footer == EmptyView {
  /// Creates a section with a string title as the header.
  ///
  /// This convenience initializer matches SwiftUI's `Section(_ title:content:)`.
  ///
  /// - Parameters:
  ///   - title: The string to use as the header text.
  ///   - content: A ViewBuilder that defines the section's main content.
  public init(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) {
    self.header = Text(title)
    self.content = content()
    self.footer = EmptyView()
  }
}

// MARK: - Section Core (Internal Rendering)

/// Internal core view that handles section rendering.
///
/// `_SectionCore` is a leaf node that renders the section's header, content,
/// and footer with appropriate styling. It conforms to `Renderable` for
/// direct buffer output.
private struct _SectionCore<Parent: View, Content: View, Footer: View>: View, Renderable {
  let header: Parent
  let content: Content
  let footer: Footer

  var body: Never {
    fatalError("_SectionCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    var lines: [String] = []

    // Render header (if not EmptyView)
    if !(header is EmptyView) {
      let headerBuffer = TUIkit.renderToBuffer(header, context: context)
      // Apply dimmed + bold styling to header
      for line in headerBuffer.lines {
        let styled = applyHeaderFooterStyle(line, bold: true)
        lines.append(styled)
      }
    }

    // Render content
    let contentBuffer = TUIkit.renderToBuffer(content, context: context)
    lines.append(contentsOf: contentBuffer.lines)

    // Render footer (if not EmptyView)
    if !(footer is EmptyView) {
      let footerBuffer = TUIkit.renderToBuffer(footer, context: context)
      // Apply dimmed styling to footer
      for line in footerBuffer.lines {
        let styled = applyHeaderFooterStyle(line, bold: false)
        lines.append(styled)
      }
    }

    return FrameBuffer(lines: lines)
  }

  /// Applies dim styling (and optionally bold) to a line.
  ///
  /// Wraps the line in ANSI dim code, with optional bold.
  private func applyHeaderFooterStyle(_ line: String, bold: Bool) -> String {
    var style = TextStyle()
    style.isDim = true
    style.isBold = bold
    return ANSIRenderer.render(line, with: style)
  }
}
