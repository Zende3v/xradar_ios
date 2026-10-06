import Testing
@testable import EONA

struct SystemMediaPlaybackStateTests {
    @Test func directEventSurvivesFilteredGetter() {
        var state = SystemMediaPlaybackState()
        state.observeEvent(true)
        state.observeSnapshot(false, reliable: false)
        state.observeSnapshot(false, reliable: true)
        #expect(state.displayed == true)
        #expect(state.requestDescription == nil)
    }

    @Test func requestRemainsDistinctUntilReliableConfirmation() {
        var state = SystemMediaPlaybackState()
        state.observeEvent(true)
        state.request(false)
        #expect(state.observed == true)
        #expect(state.displayed == false)
        #expect(state.requestDescription == "Pause demandée")
        state.observeSnapshot(true, reliable: true)
        #expect(state.requested == false)
        state.observeSnapshot(false, reliable: true)
        #expect(state.observed == false)
        #expect(state.requested == nil)
    }

    @Test func externalEventAndPlayerChangeDiscardRequest() {
        var state = SystemMediaPlaybackState()
        state.request(true)
        state.observeEvent(false)
        #expect(state.displayed == false)
        #expect(state.requested == nil)
        state.request(true)
        state.reset()
        #expect(state.displayed == nil)
        #expect(state.requestDescription == nil)
        state.observeSnapshot(true, reliable: true)
        #expect(state.displayed == true)
    }

    @Test func refusedRequestPreservesObservation() {
        var state = SystemMediaPlaybackState()
        state.observeEvent(true)
        state.request(false)
        state.cancelRequest()
        #expect(state.displayed == true)
        #expect(state.requestDescription == nil)
    }
}
