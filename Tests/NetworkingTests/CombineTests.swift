import Testing
import Foundation
@preconcurrency import Combine
@testable import Networking

struct CombineTests: @unchecked Sendable {
  struct Sample: Decodable, @unchecked Sendable {
    var message: String
  }

  let instance = Networking.shared
  static let token = "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"

  // Helper: await first value or throw on failure
  private func awaitFirst<T: Sendable>(_ pub: AnyPublisher<T, Error>) async throws -> T {
    try await withCheckedThrowingContinuation { cont in
      var didResume = false
      var cancellable: AnyCancellable?
      cancellable = pub
        .first()
        .sink(
          receiveCompletion: { completion in
            if case .failure(let error) = completion, !didResume {
              didResume = true
              cont.resume(throwing: error)
            }
            cancellable?.cancel()
          },
          receiveValue: { output in
            if !didResume {
              didResume = true
              cont.resume(returning: output)
            }
          }
        )
    }
  }

  @Test("Combine publisher success")
  func publisherSuccess() async throws {
    // Per-test session and unique path
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let request: Request = Request(
      from: "https://local-testing.com/combine/greeting",
      as: .post,
      authorization: .bearerToken(token: Self.token),
      parameters: ["name": "Quan"]
    )

    // Stub success for this test only
    MockServer.register(
      matcher: .init(
        method: "POST",
        path: "/combine/greeting",
        headers: ["Authorization": "Bearer \(Self.token)"]
      ),
      once: true
    ) { req in
      var name = "World"
      if let body = req.httpBody,
         let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
         let provided = obj["name"] as? String, !provided.isEmpty {
        name = provided
      } else if let contentLength = req.value(forHTTPHeaderField: "Content-Length"), contentLength != "0" {
        name = "Quan"
      }
      let data = try MockServer.jsonData(["message": "Hello \(name)"])
      let resp = MockServer.response(req, status: 200)
      return (resp, data)
    }

    let pub = await instance.publisher(for: Sample.self, from: request, session: session)
    let value: Sample = try await awaitFirst(pub)
    #expect(value.message == "Hello Quan")
  }

  @Test("Combine publisher bad URL error")
  func publisherBadUrlError() async throws {
    // Invalid URL triggers error before any network work/session
    let bad = Request(from: "", as: .get)
    let pub = await instance.publisher(for: Sample.self, from: bad)

    do {
      _ = try await awaitFirst(pub)
      #expect(Bool(false), "Expected badUrl to be thrown")
    } catch let e as Networking.NetworkError {
      #expect(e == .badUrl)
    }
  }

  @Test("Combine publisher HTTP error")
  func publisherHttpError() async throws {
    // Per-test session and explicit 403 stub for a unique path
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let wrong = Request(from: "https://local-testing.com/combine/forbidden", as: .get)

    MockServer.register(
      matcher: .init(method: "GET", path: "/combine/forbidden"),
      once: true
    ) { req in
      let resp = MockServer.response(req, status: 403)
      return (resp, Data())
    }

    let pub = await instance.publisher(for: Sample.self, from: wrong, session: session)

    do {
      _ = try await awaitFirst(pub)
      #expect(Bool(false), "Expected forbidden HTTP error to be thrown")
    } catch let e as Networking.NetworkError {
      #expect(e == .httpSeverSideError(Data(), statusCode: .forbidden))
    }
  }
}

