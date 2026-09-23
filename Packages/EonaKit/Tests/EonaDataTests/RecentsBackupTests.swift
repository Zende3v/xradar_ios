import Foundation
import Testing
import EonaCore
@testable import EonaData

/// Recents survive an update that comes with a fresh app container, as the session does.
@MainActor
struct RecentsBackupTests {
    static func place(_ id: String) -> Place {
        Place(id: id, name: "Lieu \(id)", subtitle: "", kind: .result, lat: 48.8, lon: 2.3)
    }

    @Test func aFreshContainerFindsTheRecentsAgain() {
        let keychain = MemorySecrets()
        let before = RecentsStore(defaults: freshDefaults(), backup: keychain)
        before.add(Self.place("a"))
        before.add(Self.place("b"))

        // The update: new, empty defaults — the Keychain is still there.
        let defaults = freshDefaults()
        let after = RecentsStore(defaults: defaults, backup: keychain)
        #expect(after.recents.map(\.id) == ["b", "a"])
        // And written back where the app reads first.
        #expect(RecentsStore(defaults: defaults).recents.map(\.id) == ["b", "a"])
    }

    @Test func turningSuggestionsOffErasesTheCopyToo() {
        let keychain = MemorySecrets()
        let store = RecentsStore(defaults: freshDefaults(), backup: keychain)
        store.add(Self.place("a"))
        store.clear()
        #expect(RecentsStore(defaults: freshDefaults(), backup: keychain).recents.isEmpty)
    }

    @Test func recentsFromBeforeTheCopyGetOne() {
        let defaults = freshDefaults()
        RecentsStore(defaults: defaults).add(Self.place("old"))
        let keychain = MemorySecrets()
        _ = RecentsStore(defaults: defaults, backup: keychain)
        #expect(RecentsStore(defaults: freshDefaults(), backup: keychain).recents.map(\.id) == ["old"])
    }
}
