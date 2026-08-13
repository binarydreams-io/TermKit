//  🖥️ TUIKit — Terminal UI Kit for Swift
//  List.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - List (Single Selection)

/// A scrollable list with keyboard navigation and single selection.
///
/// `List` displays a vertical collection of items inside a bordered container
/// with support for:
/// - Optional title in the border
/// - Optional footer (typically buttons or status text)
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single selection via optional binding
/// - Multi-selection via Set binding
/// - Scrolling with automatic viewport management
/// - Visual states for focused and selected items
///
/// ## Usage
///
/// ```swift
/// @State var selectedID: String?
///
/// List("My Items", selection: $selectedID) {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
///
/// // With footer
/// List("My Items", selection: $selectedID) {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// } footer: {
///     ButtonRow {
///         Button("Add") { }
///         Button("Remove") { }
///     }
/// }
/// ```
///
/// ## Visual States
///
/// | State | Rendering |
/// |-------|-----------|
/// | Focused + Selected | Pulsing accent background, bold |
/// | Focused only | Highlight background bar |
/// | Selected only | Dimmed accent indicator |
/// | Neither | Default foreground |
///
/// ## Scroll Indicators
///
/// When content extends beyond the viewport, scroll indicators (arrows)
/// appear at the top and/or bottom edges inside the container.
public struct List<SelectionValue: Hashable & Sendable, Content: View, Footer: View>: View {
  /// The optional title displayed in the border.
  let title: String?

  /// The content of the list (typically ForEach).
  let content: Content

  /// The footer content (optional).
  let footer: Footer?

  /// Binding for single selection (optional ID).
  let singleSelection: Binding<SelectionValue?>?

  /// Binding for multi-selection (Set of IDs).
  let multiSelection: Binding<Set<SelectionValue>>?

  /// The selection mode derived from which binding is set.
  var selectionMode: SelectionMode {
    multiSelection != nil ? .multi : .single
  }

  /// The unique focus identifier for this list.
  var focusID: String?

  /// Whether the list is disabled.
  var isDisabled: Bool

  /// The placeholder text shown when the list is empty.
  var emptyPlaceholder: String

  /// Whether to show separator before footer.
  var showFooterSeparator: Bool

  public var body: some View {
    _ListCore(
      title: title,
      content: content,
      footer: footer,
      singleSelection: singleSelection,
      multiSelection: multiSelection,
      selectionMode: selectionMode,
      focusID: focusID,
      isDisabled: isDisabled,
      emptyPlaceholder: emptyPlaceholder,
      showFooterSeparator: showFooterSeparator
    )
  }
}
