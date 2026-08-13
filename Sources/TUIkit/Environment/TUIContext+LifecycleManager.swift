//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TUIContext+LifecycleManager.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// Manages view lifecycle tracking, disappear callbacks, and async tasks.
/// All mutable state is protected by `NSLock`.
final class LifecycleManager: @unchecked Sendable {
  private struct Slot: Hashable, Sendable {
    let value: String

    init(token: String) {
      self.value = "token:\(token)"
    }

    init(identity: ViewIdentity) {
      self.value = "identity:\(identity.path)"
    }
  }

  private struct TaskID: Equatable, @unchecked Sendable {
    let value: AnyHashable
  }

  private struct TaskRecord: @unchecked Sendable {
    let id: TaskID?
    let task: Task<Void, Never>
  }

  private let lock = NSLock()
  private var appearedSlots: Set<Slot> = []
  private var visibleSlots: Set<Slot> = []
  private var currentRenderSlots: Set<Slot> = []
  private var disappearCallbacks: [Slot: () -> Void] = [:]
  private var tasks: [Slot: TaskRecord] = [:]
  init() {}
}

extension LifecycleManager {
  func beginRenderPass() {
    lock.lock()
    defer { lock.unlock() }
    currentRenderSlots.removeAll(keepingCapacity: true)
  }

  func endRenderPass() {
    lock.lock()
    let disappeared = visibleSlots.subtracting(currentRenderSlots).sorted {
      $0.value < $1.value
    }
    for slot in disappeared {
      appearedSlots.remove(slot)
    }
    visibleSlots = currentRenderSlots
    let callbacks = disappeared.compactMap { disappearCallbacks.removeValue(forKey: $0) }
    let removedTasks = disappeared.compactMap { tasks.removeValue(forKey: $0)?.task }
    lock.unlock()

    // Cancellation and callbacks run outside the lock to avoid deadlocks.
    for task in removedTasks {
      task.cancel()
    }
    for callback in callbacks {
      callback()
    }
  }

  @discardableResult
  func recordAppear(token: String, action: () -> Void) -> Bool {
    recordAppear(slot: Slot(token: token), action: action)
  }

  @discardableResult
  func recordAppear(identity: ViewIdentity, action: () -> Void) -> Bool {
    recordAppear(slot: Slot(identity: identity), action: action)
  }

  private func recordAppear(slot: Slot, action: () -> Void) -> Bool {
    lock.lock()
    currentRenderSlots.insert(slot)

    if !appearedSlots.contains(slot) {
      appearedSlots.insert(slot)
      lock.unlock()
      action()
      return true
    }
    lock.unlock()
    return false
  }

  func hasAppeared(token: String) -> Bool {
    hasAppeared(slot: Slot(token: token))
  }

  func hasAppeared(identity: ViewIdentity) -> Bool {
    hasAppeared(slot: Slot(identity: identity))
  }

  private func hasAppeared(slot: Slot) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return appearedSlots.contains(slot)
  }

  func resetAppearance(token: String) {
    resetAppearance(slot: Slot(token: token))
  }

  func resetAppearance(identity: ViewIdentity) {
    resetAppearance(slot: Slot(identity: identity))
  }

  private func resetAppearance(slot: Slot) {
    lock.lock()
    appearedSlots.remove(slot)
    lock.unlock()
  }

  func registerDisappear(token: String, action: @escaping () -> Void) {
    registerDisappear(slot: Slot(token: token), action: action)
  }

  func registerDisappear(identity: ViewIdentity, action: @escaping () -> Void) {
    registerDisappear(slot: Slot(identity: identity), action: action)
  }

  private func registerDisappear(slot: Slot, action: @escaping () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    disappearCallbacks[slot] = action
  }

  func unregisterDisappear(token: String) {
    unregisterDisappear(slot: Slot(token: token))
  }

  func unregisterDisappear(identity: ViewIdentity) {
    unregisterDisappear(slot: Slot(identity: identity))
  }

  private func unregisterDisappear(slot: Slot) {
    lock.lock()
    defer { lock.unlock() }
    disappearCallbacks.removeValue(forKey: slot)
  }

  func startTask(
    token: String,
    priority: TaskPriority,
    @_inheritActorContext operation: @escaping @isolated(any) @Sendable () async -> Void
  ) {
    replaceTask(
      slot: Slot(token: token),
      id: nil,
      priority: priority,
      operation: operation
    )
  }

  @discardableResult
  func updateTask(
    identity: ViewIdentity,
    id: some Hashable,
    priority: TaskPriority,
    @_inheritActorContext operation: @escaping @isolated(any) @Sendable () async -> Void
  ) -> Bool {
    let slot = Slot(identity: identity)
    let taskID = TaskID(value: AnyHashable(id))

    lock.lock()
    currentRenderSlots.insert(slot)
    if tasks[slot]?.id == taskID {
      lock.unlock()
      return false
    }

    let previousTask = tasks.removeValue(forKey: slot)?.task
    previousTask?.cancel()
    let task = Task(priority: priority) {
      await operation()
    }
    tasks[slot] = TaskRecord(id: taskID, task: task)
    lock.unlock()

    return true
  }

  func cancelTask(token: String) {
    cancelTask(slot: Slot(token: token))
  }

  func cancelTask(identity: ViewIdentity) {
    cancelTask(slot: Slot(identity: identity))
  }

  private func cancelTask(slot: Slot) {
    lock.lock()
    let task = tasks.removeValue(forKey: slot)?.task
    lock.unlock()
    task?.cancel()
  }

  var disappearCallbackCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return disappearCallbacks.count
  }

  var taskCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return tasks.count
  }

  func reset() {
    lock.lock()
    appearedSlots.removeAll()
    visibleSlots.removeAll()
    currentRenderSlots.removeAll()
    disappearCallbacks.removeAll()
    let runningTasks = tasks.values.map(\.task)
    tasks.removeAll()
    lock.unlock()

    for task in runningTasks {
      task.cancel()
    }
  }

  private func replaceTask(
    slot: Slot,
    id: TaskID?,
    priority: TaskPriority,
    operation: @escaping @isolated(any) @Sendable () async -> Void
  ) {
    lock.lock()
    currentRenderSlots.insert(slot)
    let previousTask = tasks.removeValue(forKey: slot)?.task
    previousTask?.cancel()
    let task = Task(priority: priority) {
      await operation()
    }
    tasks[slot] = TaskRecord(id: id, task: task)
    lock.unlock()
  }
}
