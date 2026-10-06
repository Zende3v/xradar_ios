import Testing
@testable import EONA

@MainActor
struct SystemMediaNavigationTests {
    @Test func keepsTrackChangeWhenBothTransportsExist() {
        #expect(SystemMediaNavigation.resolve(track: true, skip: true, interval: 15) == .track)
    }

    @Test func usesOnlyAdvertisedIntervalWhenTrackChangeIsAbsent() {
        #expect(SystemMediaNavigation.resolve(track: false, skip: true, interval: 30) == .skip(seconds: 30))
        #expect(SystemMediaNavigation.resolve(track: false, skip: false, interval: 30) == .unavailable)
    }

    @Test func neverInventsIntervalOrUnsupportedCapabilities() {
        let intervals: [Double?] = [nil, 0, -15, .nan, .infinity]
        for interval in intervals {
            #expect(SystemMediaNavigation.resolve(track: false, skip: true, interval: interval) == .unavailable)
        }
        #expect(SystemMediaNavigation.resolve(track: nil, skip: nil, interval: nil) == .track)
    }
}
