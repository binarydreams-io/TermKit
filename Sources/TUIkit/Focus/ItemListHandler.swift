//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ItemListHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Selection Mode

/// The selection mode for a list or table component.
public enum SelectionMode: Sendable {
  /// Single selection with optional binding (nil = no selection).
  case single

  /// Multi-selection with Set binding.
  case multi
}

// MARK: - Item List Handler

/// A reusable focus handler for list and table components.
///
/// `ItemListHandler` consolidates the navigation and selection logic shared by
/// `List` and `Table`. It handles:
/// - Focus registration with the focus manager
/// - Keyboard navigation (Up/Down/Home/End/PageUp/PageDown)
/// - Single and multi-selection modes
/// - Scroll offset management to keep the focused item visible
/// - Disabled state (prevents focus when disabled)
///
/// ## Usage
///
/// ```swift
/// // In List's renderToBuffer:
/// let handler = ItemListHandler(
///     focusID: focusID,
///     itemCount: items.count,
///     viewportHeight: visibleRows,
///     selectionMode: .single,
///     canBeFocused: !isDisabled
/// )
/// handler.singleSelection = singleSelectionBinding
/// focusManager.register(handler, inSection: sectionID)
/// ```
///
/// ## Navigation Keys
///
/// | Key | Action |
/// |-----|--------|
/// | Up | Move focus up (wrap to end) |
/// | Down | Move focus down (wrap to start) |
/// | Home | Jump to first item |
/// | End | Jump to last item |
/// | PageUp | Move up by viewport height |
/// | PageDown | Move down by viewport height |
/// | Enter/Space | Toggle selection at focused index |
final class ItemListHandler<SelectionValue: Hashable>: Focusable {
  /// The unique identifier for this focusable element.
  let focusID: String

  /// The total number of items in the list.
  var itemCount: Int

  /// The number of terminal lines in the viewport.
  var viewportHeight: Int

  /// The terminal-line height of each item, indexed by item index.
  ///
  /// An empty array means that every item is one line high.
  var rowHeights: [Int] = []

  /// The selection mode (single or multi).
  let selectionMode: SelectionMode

  /// Whether this element can currently receive focus.
  var canBeFocused: Bool

  /// Called when navigation changes the visible focus or scroll state.
  var onVisualStateChange: () -> Void = {}

  /// The currently focused item index (keyboard cursor).
  var focusedIndex: Int = 0

  /// The scroll offset (first visible item index).
  var scrollOffset: Int = 0

  /// Binding for single selection mode (optional ID).
  var singleSelection: Binding<SelectionValue?>?

  /// Binding for multi-selection mode (Set of IDs).
  var multiSelection: Binding<Set<SelectionValue>>?

  /// Maps item indices to their IDs for selection management.
  ///
  /// Entries are `nil` for non-selectable rows (e.g. section headers/footers in List).
  var itemIDs: [SelectionValue?] = []

  /// The set of indices that can be selected and focused.
  ///
  /// Headers and footers have non-selectable indices (not in this set).
  /// Only content rows have indices in `selectableIndices`.
  /// When empty, all items are considered selectable (backward compatibility).
  var selectableIndices: Set<Int> = []

  /// Creates an item list handler.
  ///
  /// - Parameters:
  ///   - focusID: The unique focus identifier.
  ///   - itemCount: The total number of items.
  ///   - viewportHeight: The number of terminal lines in the viewport.
  ///   - selectionMode: Single or multi-selection mode.
  ///   - canBeFocused: Whether this element can receive focus.
  init(
    focusID: String,
    itemCount: Int,
    viewportHeight: Int,
    selectionMode: SelectionMode,
    canBeFocused: Bool = true
  ) {
    self.focusID = focusID
    self.itemCount = itemCount
    self.viewportHeight = viewportHeight
    self.selectionMode = selectionMode
    self.canBeFocused = canBeFocused
  }
}

// MARK: - Focus Lifecycle

extension ItemListHandler {
  func onFocusLost() {
    // When focus is lost, reset focused index to the first selected item
    // (if any) so that when focus returns, the user sees the selection.
    switch selectionMode {
    case .single:
      if let selection = singleSelection?.wrappedValue,
         let index = itemIDs.firstIndex(of: selection)
      {
        focusedIndex = index
      }
    case .multi:
      if let selection = multiSelection?.wrappedValue,
         let firstSelected = selection.first,
         let index = itemIDs.firstIndex(of: firstSelected)
      {
        focusedIndex = index
      }
    }

    // Ensure scroll offset keeps focused item visible
    ensureFocusedItemVisible()
  }

  func onFocusReceived() {
    // Ensure the focused item is visible when focus is received
    ensureFocusedItemVisible()
  }
}
