import Foundation

struct GlobalHotKeyIdentity {
    private var nextID: UInt32?
    private var names: [UInt32: String] = [:]

    init(nextID: UInt32 = 1) { self.nextID = nextID == 0 ? nil : nextID }

    mutating func allocate() -> UInt32? {
        guard let id = nextID else { return nil }
        nextID = id == .max ? nil : id + 1
        return id
    }

    mutating func register(_ id: UInt32, name: String) { names[id] = name }
    mutating func invalidate() { names.removeAll() }
    func name(for id: UInt32) -> String? { names[id] }
}
