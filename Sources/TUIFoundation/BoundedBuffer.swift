public struct BoundedBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    public private(set) var droppedCount: Int
    private var storage: [Element]

    public init(capacity: Int) {
        precondition(capacity > 0, "A bounded buffer capacity must be greater than zero.")
        self.capacity = capacity
        droppedCount = 0
        storage = []
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var elements: [Element] { storage }

    public mutating func append(_ element: Element) {
        if storage.count == capacity {
            storage.removeFirst()
            droppedCount += 1
        }
        storage.append(element)
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }
}
