//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContainerView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Container Config

/// Shared visual configuration for container-type views.
///
/// Groups the common appearance properties used by ``Alert``, ``Dialog``,
/// ``Panel``, and ``Card``. Each view stores a `ContainerConfig` instead
/// of repeating the same five properties.
///
/// # Example
///
/// ```swift
/// let config = ContainerConfig(
///     borderStyle: .doubleLine,
///     borderColor: .cyan,
///     titleColor: .cyan
/// )
/// ```
struct ContainerConfig: Sendable, Equatable {
  /// The border style (nil uses appearance default).
  var borderStyle: BorderStyle?

  /// The border color (nil uses theme default).
  var borderColor: Color?

  /// The title color (nil uses theme accent).
  var titleColor: Color?

  /// The inner padding for the body content.
  var padding: EdgeInsets

  /// Whether to show a separator line between body and footer.
  var showFooterSeparator: Bool

  /// Creates a container configuration.
  ///
  /// - Parameters:
  ///   - borderStyle: The border style (default: appearance default).
  ///   - borderColor: The border color (default: theme border).
  ///   - titleColor: The title color (default: theme accent).
  ///   - padding: The inner padding (default: horizontal 1, vertical 0).
  ///   - showFooterSeparator: Show separator before footer (default: true).
  init(
    borderStyle: BorderStyle? = nil,
    borderColor: Color? = nil,
    titleColor: Color? = nil,
    padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
    showFooterSeparator: Bool = true
  ) {
    self.borderStyle = borderStyle
    self.borderColor = borderColor
    self.titleColor = titleColor
    self.padding = padding
    self.showFooterSeparator = showFooterSeparator
  }

  /// Default configuration.
  static let `default` = Self()
}

// MARK: - Container Style

/// Configuration options for container appearance.
///
/// Controls separators, backgrounds, and other visual aspects of containers.
struct ContainerStyle: Sendable, Equatable {
  /// Whether to show a separator line between header and body.
  var showHeaderSeparator: Bool

  /// Whether to show a separator line between body and footer.
  var showFooterSeparator: Bool

  /// The border style (nil uses appearance default).
  var borderStyle: BorderStyle?

  /// The border color (nil uses theme default).
  var borderColor: Color?

  /// Creates a container style with the specified options.
  ///
  /// - Parameters:
  ///   - showHeaderSeparator: Show separator after header (default: true).
  ///   - showFooterSeparator: Show separator before footer (default: true).
  ///   - borderStyle: The border style (default: appearance default).
  ///   - borderColor: The border color (default: theme border).
  init(
    showHeaderSeparator: Bool = true,
    showFooterSeparator: Bool = true,
    borderStyle: BorderStyle? = nil,
    borderColor: Color? = nil
  ) {
    self.showHeaderSeparator = showHeaderSeparator
    self.showFooterSeparator = showFooterSeparator
    self.borderStyle = borderStyle
    self.borderColor = borderColor
  }

  /// Creates a `ContainerStyle` from a ``ContainerConfig``.
  ///
  /// - Parameter config: The container configuration to use.
  init(from config: ContainerConfig) {
    self.showHeaderSeparator = true
    self.showFooterSeparator = config.showFooterSeparator
    self.borderStyle = config.borderStyle
    self.borderColor = config.borderColor
  }

  /// Default container style.
  static let `default` = Self()
}

// MARK: - Render Helper

/// Renders a `ContainerView` from a `ContainerConfig` and content/footer views.
///
/// Eliminates the duplicated `if/else` footer pattern found in Alert, Dialog,
/// Panel, and Card.
///
/// - Parameters:
///   - title: The container title (optional).
///   - config: The shared visual configuration.
///   - content: The body content view.
///   - footer: The footer view (optional).
///   - context: The current render context.
/// - Returns: The rendered frame buffer.
@MainActor
func renderContainer(
  title: String?,
  config: ContainerConfig,
  content: some View,
  footer: (some View)?,
  context: RenderContext
) -> FrameBuffer {
  let hasFooter = footer != nil
  let style = ContainerStyle(
    showHeaderSeparator: true,
    showFooterSeparator: hasFooter && config.showFooterSeparator,
    borderStyle: config.borderStyle,
    borderColor: config.borderColor
  )

  let container = ContainerView(
    title: title,
    titleColor: config.titleColor,
    style: style,
    padding: config.padding
  ) {
    content
  } footer: {
    if let footerView = footer {
      footerView
    }
  }
  return TUIkit.renderToBuffer(container, context: context)
}

// MARK: - Container View

/// A unified container with optional header, body, and footer sections.
///
/// `ContainerView` provides a consistent structure for all container-type views
/// like Panel, Card, Alert, and Dialog. It handles the rendering logic for
/// borders, separators, and section backgrounds.
///
/// ## Behavior by Appearance
///
/// - **Standard appearances** (line, rounded, doubleLine, heavy):
///   Title is rendered IN the top border. Footer is a separate section.
///
/// ## Example
///
/// ```swift
/// ContainerView(
///     title: "Settings",
///     style: ContainerStyle(showFooterSeparator: true)
/// ) {
///     Text("Option 1")
///     Text("Option 2")
/// } footer: {
///     ButtonRow {
///         Button("Save") { }
///         Button("Cancel") { }
///     }
/// }
/// ```
struct ContainerView<Content: View, Footer: View>: View {
  /// The container title (rendered in border or header section).
  let title: String?

  /// The title color.
  let titleColor: Color?

  /// The main content.
  let content: Content

  /// The footer content (typically buttons).
  let footer: Footer?

  /// The container style configuration.
  let style: ContainerStyle

  /// The inner padding for the body.
  let padding: EdgeInsets

  /// Creates a container with all options.
  ///
  /// - Parameters:
  ///   - title: The title (optional).
  ///   - titleColor: The title color (default: theme accent).
  ///   - style: The container style configuration.
  ///   - padding: Inner padding for body content.
  ///   - content: The main content.
  ///   - footer: The footer content (optional).
  init(
    title: String? = nil,
    titleColor: Color? = nil,
    style: ContainerStyle = .default,
    padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0),
    @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.title = title
    self.titleColor = titleColor
    self.style = style
    self.padding = padding
    self.content = content()
    self.footer = footer()
  }

  var body: some View {
    _ContainerViewCore(
      title: title,
      titleColor: titleColor,
      content: content,
      footer: footer,
      style: style,
      padding: padding
    )
  }
}
