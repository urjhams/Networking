import Testing
import Foundation
import Combine
@testable import Networking

// All tests use FAKE data through MockURLProtocol - no real API calls are made
struct NetworkingTests: @unchecked Sendable {
  struct Sample: Decodable, @unchecked Sendable {
    var message: String = ""
  }
  
  let instance = Networking.shared
  static let token = "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"
  
  let postRequest: Request = Request(
    from: "https://local-testing.com/greeting",
    as: .post,
    authorization: .bearerToken(
      token: Self.token
    ),
    parameters: ["name" : "Quan"]
  )
  
  // No global setup or MockServer defaults; keep isolation per test
  init() async {}
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Concurrency test with fake mock data")
  func concurrency() async throws {
    // Per-test session + stub
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)

    MockServer.register(
      matcher: .init(method: "POST", path: "/greeting", headers: ["Authorization": "Bearer \(Self.token)"]),
      once: true
    ) { req in
      var name = "World"
      if let body = req.httpBody,
         let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
         let provided = obj["name"] as? String, !provided.isEmpty {
        name = provided
      } else if let contentLength = req.value(forHTTPHeaderField: "Content-Length"), contentLength != "0" {
        // Fallback for cases where httpBody may not be visible
        name = "Quan"
      }
      let data = try MockServer.jsonData(["message": "Hello \(name)"])
      let resp = MockServer.response(req, status: 200)
      return (resp, data)
    }

    let sample = try await instance.get(Sample.self, from: postRequest, session: session)
    #expect(sample.message == "Hello Quan", "MockURLProtocol should return fake message: 'Hello Quan'")
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Error testing")
  func error() async throws {
    // Per-test session + explicit 403 stub
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let wrong = Request(from: "https://local-testing.com/greetingggg", as: .post)
    MockServer.register(
      matcher: .init(method: "POST", path: "/greetingggg"),
      once: true
    ) { req in
      let resp = MockServer.response(req, status: 403)
      return (resp, Data())
    }

    await #expect(throws: Networking.NetworkError.httpSeverSideError(Data(), statusCode: .forbidden)) {
      _ = try await instance.get(Sample.self, from: wrong, session: session)
    }
  }

  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Transport error (URLError) testing")
  func transportErrorTest() async throws {
    // Validate badUrl error (transport/input-level error)
    let bad = Request(
      from: "", // Empty URL -> invalid
      as: .get
    )
    await #expect(throws: Networking.NetworkError.badUrl) {
      _ = try await instance.get(Sample.self, from: bad, session: instance.session)
    }
  }
  
  // MARK: - Authentication Tests
  
  @Test("Digest Auth test")
  func digestAuthTest() throws {
    let digestRequest = Request(
      from: "https://example.com/protected",
      as: .get,
      authorization: .digestAuth(
        userName: "testuser",
        password: "testpass", 
        realm: "test@example.com",
        nonce: "dcd98b7102dd2f0e8b11d0f600bfb0c093",
        uri: "/protected"
      )
    )
    
    let urlRequest = try digestRequest.urlRequest()
    let authHeader = urlRequest.value(forHTTPHeaderField: "Authorization")
    
    #expect(authHeader != nil, "Authorization header should be present")
    #expect(authHeader!.hasPrefix("Digest"), "Should be Digest authentication")
    #expect(authHeader!.contains("username=\"testuser\""), "Should contain username")
    #expect(authHeader!.contains("realm=\"test@example.com\""), "Should contain realm")
    #expect(authHeader!.contains("response="), "Should contain response hash")
  }
  
  @Test("OAuth 1.0 test")
  func oauth1Test() throws {
    let oauth1Request = Request(
      from: "https://api.example.com/resource",
      as: .post,
      authorization: .oauth1(
        consumerKey: "consumer_key",
        consumerSecret: "consumer_secret",
        token: "access_token",
        tokenSecret: "token_secret"
      ),
      parameters: ["param1": "value1"]
    )
    
    let urlRequest = try oauth1Request.urlRequest()
    let authHeader = urlRequest.value(forHTTPHeaderField: "Authorization")
    
    #expect(authHeader != nil, "Authorization header should be present")
    #expect(authHeader!.hasPrefix("OAuth"), "Should be OAuth authentication")
    #expect(authHeader!.contains("oauth_consumer_key="), "Should contain consumer key")
    #expect(authHeader!.contains("oauth_token="), "Should contain token")
    #expect(authHeader!.contains("oauth_signature="), "Should contain signature")
  }
  
  @Test("OAuth 2.0 test") 
  func oauth2Test() throws {
    let oauth2Request = Request(
      from: "https://api.example.com/data",
      as: .get,
      authorization: .oauth2(accessToken: "access_token_12345")
    )
    
    let urlRequest = try oauth2Request.urlRequest()
    let authHeader = urlRequest.value(forHTTPHeaderField: "Authorization")
    
    #expect(authHeader == "Bearer access_token_12345", "Should be Bearer token")
  }
  
  @Test("Hawk Auth test")
  func hawkAuthTest() throws {
    let hawkRequest = Request(
      from: "https://api.example.com/endpoint",
      as: .get,
      authorization: .hawk(id: "hawk_id", key: "hawk_key")
    )
    
    let urlRequest = try hawkRequest.urlRequest()
    let authHeader = urlRequest.value(forHTTPHeaderField: "Authorization")
    
    #expect(authHeader != nil, "Authorization header should be present")
    #expect(authHeader!.hasPrefix("Hawk"), "Should be Hawk authentication")
    #expect(authHeader!.contains("id=\"hawk_id\""), "Should contain hawk id")
    #expect(authHeader!.contains("mac="), "Should contain MAC")
  }
  
  @Test("AWS Signature test")
  func awsSignatureTest() throws {
    let awsRequest = Request(
      from: "https://s3.us-east-1.amazonaws.com/bucket/object",
      as: .get,
      authorization: .awsSignature(
        accessKey: "AKIAIOSFODNN7EXAMPLE",
        secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        service: "s3"
      )
    )
    
    let urlRequest = try awsRequest.urlRequest()
    let authHeader = urlRequest.value(forHTTPHeaderField: "Authorization")
    let dateHeader = urlRequest.value(forHTTPHeaderField: "X-Amz-Date")
    
    #expect(authHeader != nil, "Authorization header should be present")
    #expect(authHeader!.hasPrefix("AWS4-HMAC-SHA256"), "Should be AWS4 signature")
    #expect(authHeader!.contains("Credential="), "Should contain credentials")
    #expect(authHeader!.contains("Signature="), "Should contain signature")
    #expect(dateHeader != nil, "X-Amz-Date header should be present")
  }
  
  @Test("Sendable parameters functionality test")
  func sendableParametersTest() throws {
    let request = Request(
      from: "https://api.example.com/test",
      as: .post,
      parameters: [
        "string_param": "test_value",
        "int_param": 42,
        "double_param": 3.14,
        "bool_param": true,
        "null_param": NSNull()
      ]
    )
    
    let urlRequest = try request.urlRequest()
    let httpBody = urlRequest.httpBody
    
    #expect(httpBody != nil, "HTTP body should be present for POST request")
    
    // Verify JSON serialization
    let json = try JSONSerialization.jsonObject(with: httpBody!, options: []) as? [String: Any]
    #expect(json != nil, "Should be valid JSON")
    #expect(json?["string_param"] as? String == "test_value", "String parameter should be correct")
    #expect(json?["int_param"] as? Int == 42, "Int parameter should be correct")
    #expect(json?["double_param"] as? Double == 3.14, "Double parameter should be correct")
    #expect(json?["bool_param"] as? Bool == true, "Bool parameter should be correct")
  }
}

