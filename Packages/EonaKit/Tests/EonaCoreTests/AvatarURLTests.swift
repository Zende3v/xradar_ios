import Foundation
import Testing
import EonaCore

struct AvatarURLTests {
    let base = URL(string: "https://api.example.test/")!

    @Test func onlyBackendPhotosAreLoaded() {
        for file in ["driver-1.png", "driver-1.jpg?v=123", "driver_2.webp"] {
            let address = "https://api.example.test/avatars/\(file)"
            #expect(AvatarURL.allowed(address, baseURL: base)?.absoluteString == address)
        }
        for address in [
            "https://tracker.test/photo.jpg", "//tracker.test/photo.jpg", "http://api.example.test/avatars/a.jpg",
            "https://api.example.test.tracker.test/avatars/a.jpg", "https://api.example.test:444/avatars/a.jpg",
            "https://user:pass@api.example.test/avatars/a.jpg", "https://api.example.test/avatars/a.jpg#tracker",
            "https://api.example.test/avatars/a.svg", "https://api.example.test/avatars/a.jpg/extra",
            "https://api.example.test/avatars/%61.jpg", "https://api.example.test/avatars/a.jpg?v=1&v=2",
            "https://api.example.test/avatars/a.jpg?url=https://tracker.test", "https://api.example.test/avatars/a.jpg?v=text",
            "data:image/png;base64,aGVsbG8=", "https://api.example.test/api/avatar/a.jpg",
        ] {
            #expect(AvatarURL.allowed(address, baseURL: base) == nil)
        }
        #expect(AvatarURL.allowed(nil, baseURL: base) == nil)
    }

    @Test func backendPathAndPortAreRespected() {
        let custom = URL(string: "http://localhost:8080/eona/")!
        #expect(AvatarURL.allowed("http://localhost:8080/eona/avatars/a.jpg", baseURL: custom) != nil)
        #expect(AvatarURL.allowed("http://localhost:8080/avatars/a.jpg", baseURL: custom) == nil)
        #expect(AvatarURL.allowed("http://localhost/eona/avatars/a.jpg", baseURL: custom) == nil)
    }
}
