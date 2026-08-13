//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Image+Modifiers.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - View Modifiers

extension View {
  /// Sets the character set for ASCII art image rendering.
  ///
  /// - Parameter characterSet: The character set to use.
  /// - Returns: A modified view.
  public func imageCharacterSet(_ characterSet: ASCIICharacterSet) -> some View {
    environment(\.imageCharacterSet, characterSet)
  }

  /// Sets the color mode for ASCII art image rendering.
  ///
  /// - Parameter colorMode: The color mode to use.
  /// - Returns: A modified view.
  public func imageColorMode(_ colorMode: ASCIIColorMode) -> some View {
    environment(\.imageColorMode, colorMode)
  }

  /// Sets the dithering mode for ASCII art image rendering.
  ///
  /// - Parameter dithering: The dithering algorithm.
  /// - Returns: A modified view.
  public func imageDithering(_ dithering: DitheringMode) -> some View {
    environment(\.imageDithering, dithering)
  }

  /// Sets the placeholder text shown while an image is loading.
  ///
  /// - Parameter text: The placeholder text, or nil for no text.
  /// - Returns: A modified view.
  public func imagePlaceholder(_ text: String?) -> some View {
    environment(\.imagePlaceholderText, text)
  }

  /// Controls whether a spinner is shown while an image is loading.
  ///
  /// - Parameter showSpinner: Whether to show a spinner.
  /// - Returns: A modified view.
  public func imagePlaceholderSpinner(_ showSpinner: Bool) -> some View {
    environment(\.imagePlaceholderSpinner, showSpinner)
  }

  /// Sets the aspect ratio and content mode for image rendering.
  ///
  /// Use this modifier to control how images are scaled within their
  /// available space.
  ///
  /// ```swift
  /// // Use natural aspect ratio, fit within bounds
  /// Image(.file("photo.png"))
  ///     .aspectRatio(contentMode: .fit)
  ///
  /// // Force 16:9 ratio, fill bounds
  /// Image(.url("https://example.com/banner.png"))
  ///     .aspectRatio(16.0/9.0, contentMode: .fill)
  /// ```
  ///
  /// - Parameters:
  ///   - aspectRatio: The ratio of width to height to use for the
  ///     resulting view. Use `nil` to maintain the source image's
  ///     natural aspect ratio.
  ///   - contentMode: A flag that indicates whether this view fits or
  ///     fills the parent context.
  /// - Returns: A view that constrains this view's dimensions to the
  ///   given aspect ratio and content mode.
  public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
    environment(\.imageContentMode, contentMode)
      .environment(\.imageAspectRatio, aspectRatio)
  }

  /// Scales this view to fit within the parent while maintaining the
  /// aspect ratio.
  ///
  /// Equivalent to `.aspectRatio(contentMode: .fit)`.
  ///
  /// - Returns: A view that scales to fit.
  public func scaledToFit() -> some View {
    aspectRatio(contentMode: .fit)
  }

  /// Scales this view to fill the parent while maintaining the
  /// aspect ratio.
  ///
  /// Equivalent to `.aspectRatio(contentMode: .fill)`.
  ///
  /// - Returns: A view that scales to fill.
  public func scaledToFill() -> some View {
    aspectRatio(contentMode: .fill)
  }

  /// Sets the maximum allowed pixel count for image loading.
  ///
  /// Images with more total pixels than this limit will fail to load
  /// with `ImageLoadError.imageTooLarge`. Use this to prevent excessive
  /// memory usage from very large images.
  ///
  /// ```swift
  /// Image(.url("https://example.com/photo.png"))
  ///     .imageMaxPixelCount(4_000_000)  // ~4 megapixels
  /// ```
  ///
  /// - Parameter maxPixels: The maximum total pixel count, or `nil` for no limit.
  /// - Returns: A modified view.
  public func imageMaxPixelCount(_ maxPixels: Int?) -> some View {
    environment(\.imageMaxPixelCount, maxPixels)
  }

  /// Sets the timeout for URL image downloads.
  ///
  /// If the download does not complete within the specified interval,
  /// it fails with `ImageLoadError.downloadFailed`.
  ///
  /// ```swift
  /// Image(.url("https://example.com/photo.png"))
  ///     .imageURLTimeout(10)  // 10 seconds
  /// ```
  ///
  /// - Parameter seconds: The timeout in seconds (default: 30).
  /// - Returns: A modified view.
  public func imageURLTimeout(_ seconds: TimeInterval) -> some View {
    environment(\.imageURLTimeout, seconds)
  }
}
