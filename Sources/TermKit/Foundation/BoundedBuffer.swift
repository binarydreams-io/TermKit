/// A fixed-capacity buffer that discards its oldest element when full.
public struct BoundedBuffer<Element: Sendable>: Sendable {
  /// The maximum number of stored elements.
  public let capacity: Int
  /// The number of elements discarded since initialization.
  public private(set) var droppedCount: Int
  private var storage: [Element]

  /// Creates an empty buffer with the specified capacity.
  public init(capacity: Int) {
    precondition(capacity > 0, "A bounded buffer capacity must be greater than zero.")
    self.capacity = capacity
    self.droppedCount = 0
    self.storage = []
    storage.reserveCapacity(capacity)
  }

  /// The number of stored elements.
  public var count: Int {
    storage.count
  }

  /// A Boolean value that indicates whether the buffer contains no elements.
  public var isEmpty: Bool {
    storage.isEmpty
  }

  /// A copy of the stored elements in insertion order.
  public var elements: [Element] {
    storage
  }

  /// Appends an element and discards the oldest element when the buffer is full.
  public mutating func append(_ element: Element) {
    if storage.count == capacity {
      storage.removeFirst()
      droppedCount += 1
    }
    storage.append(element)
  }

  /// Removes all stored elements.
  public mutating func removeAll(keepingCapacity: Bool = true) {
    storage.removeAll(keepingCapacity: keepingCapacity)
  }
}
