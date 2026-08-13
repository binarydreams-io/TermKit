//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ProgressView+Initializers.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Initializers (value/total)

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
  /// Creates a progress view with a fractional completion value.
  ///
  /// - Parameters:
  ///   - value: The completed amount (nil for indeterminate).
  ///   - total: The total amount (default: 1.0).
  public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
    self.fractionCompleted = Self.normalizedFraction(value: value, total: total)
    self.style = .block
    self.label = nil
    self.currentValueLabel = nil
  }
}

extension ProgressView where CurrentValueLabel == EmptyView {
  /// Creates a progress view with a label.
  ///
  /// - Parameters:
  ///   - value: The completed amount (nil for indeterminate).
  ///   - total: The total amount (default: 1.0).
  ///   - label: A view that describes the task in progress.
  public init<V: BinaryFloatingPoint>(
    value: V?, total: V = 1.0,
    @ViewBuilder label: () -> Label
  ) {
    self.fractionCompleted = Self.normalizedFraction(value: value, total: total)
    self.style = .block
    self.label = label()
    self.currentValueLabel = nil
  }
}

extension ProgressView {
  /// Creates a progress view with a label and current value label.
  ///
  /// - Parameters:
  ///   - value: The completed amount (nil for indeterminate).
  ///   - total: The total amount (default: 1.0).
  ///   - label: A view that describes the task in progress.
  ///   - currentValueLabel: A view showing the current progress value.
  public init<V: BinaryFloatingPoint>(
    value: V?, total: V = 1.0,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
    self.fractionCompleted = Self.normalizedFraction(value: value, total: total)
    self.style = .block
    self.label = label()
    self.currentValueLabel = currentValueLabel()
  }
}

// MARK: - String Title Initializer

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
  /// Creates a progress view with a string title.
  ///
  /// - Parameters:
  ///   - title: A string that describes the task in progress.
  ///   - value: The completed amount (nil for indeterminate).
  ///   - total: The total amount (default: 1.0).
  // swiftformat:disable:next opaqueGenericParameters
  public init<S: StringProtocol, V: BinaryFloatingPoint>(
    _ title: S, value: V?, total: V = 1.0
  ) {
    self.fractionCompleted = Self.normalizedFraction(value: value, total: total)
    self.style = .block
    self.label = Text(String(title))
    self.currentValueLabel = nil
  }
}
