//  TUIKit - Terminal UI Kit for Swift
//  Slider+Configuration.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Slider Initializers (No Label)

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
  /// Creates a slider to select a value from a given range.
  ///
  /// - Parameters:
  ///   - value: The selected value within `bounds`.
  ///   - bounds: The range of valid values. Defaults to `0...1`.
  ///   - step: The distance between each valid value. Defaults to `0.01`.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0 ... 1,
    step: V.Stride = 0.01,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where V.Stride: BinaryFloatingPoint {
    self.value = Binding(
      get: { Double(value.wrappedValue) },
      set: { value.wrappedValue = V($0) }
    )
    self.bounds = Double(bounds.lowerBound) ... Double(bounds.upperBound)
    self.step = Double(step)
    self.label = nil
    self.valueLabel = nil
    self.trackStyle = .block
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }
}

// MARK: - Slider Initializers (String Title)

extension Slider where Label == Text, ValueLabel == EmptyView {
  /// Creates a slider with a title string.
  ///
  /// - Parameters:
  ///   - title: The title of the slider.
  ///   - value: The selected value within `bounds`.
  ///   - bounds: The range of valid values. Defaults to `0...1`.
  ///   - step: The distance between each valid value. Defaults to `0.01`.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init<V: BinaryFloatingPoint>(
    _ title: some StringProtocol,
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0 ... 1,
    step: V.Stride = 0.01,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where V.Stride: BinaryFloatingPoint {
    self.value = Binding(
      get: { Double(value.wrappedValue) },
      set: { value.wrappedValue = V($0) }
    )
    self.bounds = Double(bounds.lowerBound) ... Double(bounds.upperBound)
    self.step = Double(step)
    self.label = Text(String(title))
    self.valueLabel = nil
    self.trackStyle = .block
    // Auto-generated focusID from view identity (collision-free)
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }
}

// MARK: - Slider Initializers (ViewBuilder Label)

extension Slider where ValueLabel == EmptyView {
  /// Creates a slider with a custom label.
  ///
  /// - Parameters:
  ///   - value: The selected value within `bounds`.
  ///   - bounds: The range of valid values. Defaults to `0...1`.
  ///   - step: The distance between each valid value. Defaults to `0.01`.
  ///   - label: A view describing the purpose of the slider.
  ///   - onEditingChanged: A callback for when editing begins and ends.
  public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0 ... 1,
    step: V.Stride = 0.01,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where V.Stride: BinaryFloatingPoint {
    self.value = Binding(
      get: { Double(value.wrappedValue) },
      set: { value.wrappedValue = V($0) }
    )
    self.bounds = Double(bounds.lowerBound) ... Double(bounds.upperBound)
    self.step = Double(step)
    self.label = label()
    self.valueLabel = nil
    self.trackStyle = .block
    self.focusID = nil
    self.isDisabled = false
    self.onEditingChanged = onEditingChanged
  }
}

// MARK: - Slider Modifiers

extension Slider {
  /// Sets the visual style of the slider track.
  ///
  /// ```swift
  /// Slider(value: $volume)
  ///     .trackStyle(.dot)
  /// ```
  ///
  /// - Parameter style: The track style.
  /// - Returns: A slider with the specified track style.
  public func trackStyle(_ style: TrackStyle) -> Slider {
    var copy = self
    copy.trackStyle = style
    return copy
  }

  /// Creates a disabled version of this slider.
  ///
  /// - Parameter disabled: Whether the slider is disabled.
  /// - Returns: A new slider with the disabled state.
  public func disabled(_ disabled: Bool = true) -> Slider {
    var copy = self
    copy.isDisabled = disabled
    return copy
  }

  /// Sets a custom focus identifier for this slider.
  ///
  /// - Parameter id: The unique focus identifier.
  /// - Returns: A slider with the specified focus identifier.
  public func focusID(_ id: String) -> Slider {
    var copy = self
    copy.focusID = id
    return copy
  }
}
