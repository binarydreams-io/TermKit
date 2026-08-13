//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Alert+ButtonProvider.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Button Provider Protocol

/// A protocol for views that can provide `Button` instances.
///
/// This replaces the fragile `Mirror`-based button extraction with a
/// compile-time safe, protocol-based approach. Each view type that may
/// contain buttons in an Alert's actions closure conforms to this protocol.
@MainActor
protocol ButtonProvider {
  /// Extracts all `Button` instances contained in this view.
  func extractButtons() -> [Button]
}

// MARK: - ButtonProvider Conformances

extension Button: ButtonProvider {
  func extractButtons() -> [Button] {
    [self]
  }
}

extension EmptyView: ButtonProvider {
  func extractButtons() -> [Button] {
    []
  }
}

extension TupleView: ButtonProvider {
  func extractButtons() -> [Button] {
    var buttons: [Button] = []
    func collect(_ view: some View) {
      if let provider = view as? ButtonProvider {
        buttons.append(contentsOf: provider.extractButtons())
      }
    }
    repeat collect(each children)
    return buttons
  }
}
