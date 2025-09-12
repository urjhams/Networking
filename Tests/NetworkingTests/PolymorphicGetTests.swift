import Testing
import Foundation
@testable import Networking

@Suite(.serialized)
struct PolymorphicGetTests {
  struct TypeA: ConcurencyDecodable { let id: Int }
  struct TypeB: ConcurencyDecodable { let message: String; let code: Int }

  let instance = Networking.shared

  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Decodes the second of two types")
  func decodesSecondType() async throws {
    // Arrange a stub that matches TypeB only
    MockServer.register(matcher: .init(method: "GET", path: "/either"), once: true) { req in
      let data = try MockServer.jsonData(["message": "Hi", "code": 7])
      let resp = MockServer.response(req, status: 200)
      return (resp, data)
    }

    let request = Request(from: "https://local-testing.com/either", as: .get)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)

    // Act
    let value = try await instance.get(
      possibleType: [TypeA.self, TypeB.self],
      from: request,
      session: session
    )

    // Assert: should be TypeB (second type)
    guard let decoded = value as? TypeB else {
      #expect(Bool(false), "Expected to decode TypeB as the second candidate")
      return
    }
    #expect(decoded.message == "Hi")
    #expect(decoded.code == 7)
  }

  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Throws when none of the types match")
  func throwsWhenNoTypeMatches() async throws {
    // Arrange a stub that matches neither TypeA nor TypeB
    MockServer.register(matcher: .init(method: "GET", path: "/none"), once: true) { req in
      let data = try MockServer.jsonData(["unexpected": true])
      let resp = MockServer.response(req, status: 200)
      return (resp, data)
    }

    let request = Request(from: "https://local-testing.com/none", as: .get)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)

    // Act + Assert
    await #expect(throws: Networking.NetworkError.jsonFormatError) {
      _ = try await instance.get(
        possibleType: [TypeA.self, TypeB.self],
        from: request,
        session: session
      )
    }
  }
}
