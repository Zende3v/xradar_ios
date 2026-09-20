import Foundation
import Testing
@testable import EonaData

struct BackendConfigurationTests {
    @Test func acceptsAbsoluteHTTPSURL() throws {
        let configuration = try #require(BackendConfiguration(string: " https://api.lrda-mercuriale.uk/ "))
        #expect(configuration.baseURL.host() == "api.lrda-mercuriale.uk")
        #expect(configuration.baseURL.scheme == "https")
    }

    @Test(arguments: [nil, "", "   ", "api.lrda-mercuriale.uk", "ftp://host/", "https://"] as [String?])
    func rejectsInvalidValues(_ value: String?) {
        #expect(BackendConfiguration(string: value) == nil)
    }

    @Test func productionPointsAtTheVPS() {
        #expect(BackendConfiguration.production.baseURL.absoluteString == "https://api.lrda-mercuriale.uk/")
    }
}
