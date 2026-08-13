//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ChildInfo+Resolution.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Child Info Resolution

/// Resolves child infos from a view's content.
///
/// If the content conforms to ``ChildInfoProvider`` (e.g. TupleViews),
/// it returns individual child infos. Otherwise it returns the content
/// as a single-element array.
///
/// - Parameters:
///   - content: The content view.
///   - context: The rendering context.
/// - Returns: An array of ``ChildInfo``.
@MainActor
public func resolveChildInfos(from content: some View, context: RenderContext) -> [ChildInfo] {
  if let provider = content as? ChildInfoProvider {
    return provider.childInfos(context: context)
  }
  return [makeChildInfo(for: content, context: context)]
}

// MARK: - Two-Pass Layout Resolution

/// Resolves child views from a view's content for two-pass layout.
///
/// If the content conforms to ``ChildViewProvider`` (e.g. TupleViews),
/// it returns individual child views. Otherwise it wraps the content
/// in a single-element array.
///
/// - Parameters:
///   - content: The content view.
///   - context: The rendering context.
/// - Returns: An array of ``ChildView``.
@MainActor
public func resolveChildViews(from content: some View, context: RenderContext) -> [ChildView] {
  if let provider = content as? ChildViewProvider {
    return provider.childViews(context: context)
  }
  return [ChildView(content)]
}
