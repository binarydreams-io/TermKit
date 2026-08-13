//  TUIKit - Terminal UI Kit for Swift
//  TabView+Rendering.swift
//
//  Created by LAYERED.work
//  License: MIT

extension TabView {
  public var body: some View {
    VStack(spacing: 0) {
      _TabBarCore(selection: selection, tabs: tabs)
      content(selection.wrappedValue)
    }
  }
}

// MARK: - Tab Bar Cell

/// One rendered tab: the text it prints and the columns it owns.
struct _TabBarCell {
  /// The tab's index in the bar, which its click region keeps.
  let index: Int

  /// The cell's text, ANSI codes included.
  let text: String

  /// The columns the cell owns, including any gap that follows it.
  let width: Int
}

// MARK: - Internal Tab Bar Core

/// Internal view that renders the one-line clickable tab bar.
///
/// The bar's look comes from the environment's ``TabBarStyle``. This file
/// renders the filled default; `TabView+PlainBar.swift` renders the plain
/// style. Both produce ``_TabBarCell`` values, and ``buffer(for:availableWidth:context:)``
/// joins them into the bar line and registers one click region per cell.
struct _TabBarCore<Value: Hashable & Sendable>: View, Renderable {
  let selection: Binding<Value>
  let tabs: [TabItem<Value>]

  /// The columns one filled tab needs: the cell padding plus one label column.
  ///
  /// A bar that divides the offered width by the tab count alone overflows the
  /// terminal as soon as there are more tabs than columns, and the too-long
  /// line wraps, which pushes every row below the bar out of place.
  private static var minimumTabWidth: Int {
    3
  }

  var body: Never {
    fatalError("_TabBarCore renders via Renderable")
  }

  func renderToBuffer(context: RenderContext) -> FrameBuffer {
    let availableWidth = max(0, context.availableWidth)
    guard !tabs.isEmpty, availableWidth > 0 else {
      return FrameBuffer(lines: [""])
    }

    let palette = context.environment.palette
    let cells: [_TabBarCell] = switch context.environment.tabBarStyle {
    case .filled: filledCells(availableWidth: availableWidth, palette: palette)
    case .plain: plainCells(availableWidth: availableWidth, palette: palette)
    }
    return buffer(for: cells, availableWidth: availableWidth, context: context)
  }

  /// Whether the tab is the open one.
  func isSelected(_ tab: TabItem<Value>) -> Bool {
    tab.value == selection.wrappedValue
  }

  /// The index of the selected tab, or the first tab when the selection
  /// matches none of them.
  var selectedIndex: Int {
    tabs.firstIndex { isSelected($0) } ?? 0
  }

  /// The label a cell prints: the tab's label and its badge, if it has one.
  func label(of tab: TabItem<Value>) -> String {
    tab.badge.map { "\(tab.label) \($0)" } ?? tab.label
  }

  /// Joins the cells into the bar line and registers one click region per cell.
  ///
  /// The line pads to the offered width so the bar stays one full row, whatever
  /// width its cells spend.
  private func buffer(
    for cells: [_TabBarCell],
    availableWidth: Int,
    context: RenderContext
  ) -> FrameBuffer {
    let interactionDispatcher = context.isMeasuring ? nil : context.environment.interactionDispatcher
    var line = ""
    var regions: [InteractionRegion] = []
    var x = 0

    for cell in cells {
      line += cell.text

      if let interactionDispatcher {
        let id = "tab-\(context.identity.path)-\(cell.index)"
        let binding = selection
        let value = tabs[cell.index].value
        interactionDispatcher.registerClick(id: id) {
          binding.wrappedValue = value
        }
        regions.append(
          InteractionRegion(id: id, rect: TerminalCellRect(x: x, y: 0, width: cell.width, height: 1))
        )
      }

      x += cell.width
    }

    return FrameBuffer(lines: [line.padToVisibleWidth(availableWidth)], regions: regions)
  }
}

// MARK: - Filled Bar

extension _TabBarCore {
  /// The cells of the filled bar: equal shares of the offered width, the
  /// selected one painted with the accent.
  private func filledCells(availableWidth: Int, palette: any Palette) -> [_TabBarCell] {
    let visible = visibleIndices(availableWidth: availableWidth)
    let count = visible.count
    let tabWidth = max(1, availableWidth / count)
    let remainder = max(0, availableWidth - tabWidth * count)
    var cells: [_TabBarCell] = []

    for (position, index) in visible.enumerated() {
      let tab = tabs[index]
      let width = tabWidth + (position == count - 1 ? remainder : 0)
      let isActive = isSelected(tab)
      let text = filledText(
        for: tab,
        width: width,
        foreground: isActive ? palette.background : palette.foreground,
        background: isActive ? palette.accent : palette.focusBackground
      )
      cells.append(_TabBarCell(index: index, text: text, width: width))
    }

    return cells
  }

  /// The tabs the filled bar shows, as indices into ``tabs``.
  ///
  /// A width that cannot hold every tab at ``minimumTabWidth`` shows the tabs
  /// that fit, in a window that ends on the selected tab, so the bar never
  /// leaves the open tab out. The dropped tabs keep working through their
  /// values; only their cells are gone.
  ///
  /// - Parameter availableWidth: The columns the bar may spend.
  /// - Returns: The indices of the tabs to render, in display order.
  private func visibleIndices(availableWidth: Int) -> Range<Int> {
    let capacity = max(1, availableWidth / Self.minimumTabWidth)
    guard capacity < tabs.count else { return tabs.indices }
    let start = min(max(0, selectedIndex - capacity + 1), tabs.count - capacity)
    return start ..< start + capacity
  }

  /// Builds one filled tab's colored, width-fitted cell text.
  ///
  /// Padding happens on the plain string first so the background color
  /// covers the full tab width. Truncation happens after colorizing, using
  /// `ansiAwarePrefix` so a label longer than the tab keeps its trailing
  /// reset code instead of bleeding color into the next tab.
  private func filledText(
    for tab: TabItem<Value>,
    width: Int,
    foreground: Color,
    background: Color
  ) -> String {
    let hintPrefix = tab.hint.map { "\($0) " } ?? ""
    let raw = " \(hintPrefix)\(label(of: tab)) "
    let padded = raw.padToVisibleWidth(width)
    let colored = ANSIRenderer.colorize(padded, foreground: foreground, background: background)
    return colored.ansiAwarePrefix(visibleCount: width)
  }
}
