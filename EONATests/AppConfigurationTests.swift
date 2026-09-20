import Foundation
import Testing
@testable import EONA

@MainActor
struct AppConfigurationTests {
    @Test func readsTheBackend() {
        let configuration = AppConfiguration(info: ["XRBackendURL": "https://example.org/"])
        #expect(configuration.backend.baseURL.absoluteString == "https://example.org/")
    }

    @Test func fallsBackWhenTheBackendIsMissingOrBlank() {
        #expect(AppConfiguration(info: ["XRBackendURL": ""]).backend == .production)
        #expect(AppConfiguration(info: [:]).backend == .production)
    }

    @Test func bundleCarriesTheBackendURL() {
        #expect(AppConfiguration.current.backend.baseURL.scheme == "https")
    }
}
