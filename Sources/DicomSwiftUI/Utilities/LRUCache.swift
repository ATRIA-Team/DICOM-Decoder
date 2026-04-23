import Foundation

/// A lightweight generic LRU cache using a doubly-linked list and a dictionary.
/// Provides O(1) time complexity for get and put operations.
internal final class LRUCache<Key: Hashable, Value> {
    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    private let capacity: Int
    private var dict = [Key: Node]()
    private var head: Node?
    private var tail: Node?
    
    /// Initializes a new LRUCache with the specified capacity.
    /// - Parameter capacity: Maximum number of items the cache can hold. Must be > 0.
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }
    
    /// Retrieves a value for a key and marks it as recently used.
    /// - Parameter key: The key to look up.
    /// - Returns: The cached value, or nil if not found.
    func get(_ key: Key) -> Value? {
        guard let node = dict[key] else { return nil }
        moveToHead(node)
        return node.value
    }
    
    /// Inserts or updates a value for a key and marks it as recently used.
    /// If the cache exceeds capacity, the least recently used item is evicted.
    /// - Parameters:
    ///   - key: The key to insert or update.
    ///   - value: The value to cache.
    func put(_ key: Key, value: Value) {
        if let node = dict[key] {
            node.value = value
            moveToHead(node)
        } else {
            let newNode = Node(key: key, value: value)
            dict[key] = newNode
            addToHead(newNode)
            
            if dict.count > capacity {
                removeTail()
            }
        }
    }
    
    /// Clears all entries from the cache.
    func clear() {
        dict.removeAll()
        head = nil
        tail = nil
    }
    
    private func moveToHead(_ node: Node) {
        if head === node { return }
        
        // Detach
        node.prev?.next = node.next
        node.next?.prev = node.prev
        
        if tail === node {
            tail = node.prev
        }
        
        // Move to head
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node
    }
    
    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }
    
    private func removeTail() {
        guard let oldTail = tail else { return }
        dict.removeValue(forKey: oldTail.key)
        
        tail = oldTail.prev
        tail?.next = nil
        
        if tail == nil {
            head = nil
        }
    }
}
