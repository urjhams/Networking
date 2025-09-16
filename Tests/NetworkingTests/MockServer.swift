import Foundation

/// Simple stubbing utility for tests: allows registering multiple endpoints and responses via matchers.
/// Thread-safe using a private serial queue; intended for Tests target only.
enum MockServer {
  struct Matcher: Equatable {
    let method: String?
    let path: String?
    let headers: [String: String]?

    init(method: String? = nil, path: String? = nil, headers: [String: String]? = nil) {
      self.method = method
      self.path = path
      self.headers = headers
    }

    func matches(_ request: URLRequest) -> Bool {
      if let method = method, request.httpMethod?.uppercased() != method.uppercased() {
        return false
      }
      
      if let path = path, request.url?.path != path {
        return false 
      }
      
      if let headers = headers {
        for (k, v) in headers {
          if request.value(forHTTPHeaderField: k) != v { 
            return false 
          }
        }
      }
      return true
    }
  }

  struct Stub {
    let matcher: Matcher
    let once: Bool
    let priority: Int
    let handler: (URLRequest) throws -> (HTTPURLResponse, Data)
  }

  // MARK: - Storage
  nonisolated(unsafe) private static var queue = DispatchQueue(label: "MockServer.queue")
  nonisolated(unsafe) private static var stubs: [Stub] = []
  nonisolated(unsafe) private static var defaultHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  // MARK: - Public API
  static func clear() {
    queue.sync {
      stubs.removeAll()
      defaultHandler = nil
    }
  }

  static func setDefault(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
    queue.sync { defaultHandler = handler }
  }

  static func register(
    matcher: Matcher,
     once: Bool = false, 
     priority: Int = 0,
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) {
    queue.sync { 
      stubs.append(Stub(matcher: matcher, once: once, priority: priority, handler: handler)) 
    }
  }

  static func registerOnce(
    matcher: Matcher,
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) {
    register(matcher: matcher, once: true, priority: 0, handler: handler)
  }

  /// Register a stub that throws a transport-level error for the given matcher.
  static func registerNetworkError(matcher: Matcher, once: Bool = true, error: Error) {
    register(matcher: matcher, once: once, priority: 1) { _ in
      throw error
    }
  }

  /// Resolve a response for the given request (used by URLProtocol).
  static func resolve(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
    // Pick the best matching stub; remove it if marked as `once`.
    if let chosen = queue.sync(execute: { () -> Stub? in
      // Choose the most specific match (more conditions). Tie-breaker prefers later registrations.
      var bestIndex: Int?
      var bestScore = -1
      var bestPriority = Int.min

      for (idx, s) in stubs.enumerated() where s.matcher.matches(request) {
        let score =
          (s.matcher.method == nil ? 0 : 1) +
          (s.matcher.path == nil ? 0 : 1) +
          (s.matcher.headers?.count ?? 0)
        if s.priority > bestPriority || 
          (s.priority == bestPriority && (score > bestScore || (score == bestScore && (bestIndex == nil || idx > bestIndex!)))) {
            bestIndex = idx
            bestScore = score
            bestPriority = s.priority
        }
      }

      if let idx = bestIndex {
        let s = stubs[idx]
        if s.once { stubs.remove(at: idx) }
        return s
      }
      return nil
    }) {
      return try chosen.handler(request)
    }

    if let def = queue.sync(execute: { defaultHandler }) {
      return try def(request)
    }

    // No stub configured: return 501 to surface missing configuration.
    let url = request.url ?? URL(string: "about:blank")!
    let resp = HTTPURLResponse(url: url, statusCode: 501, httpVersion: nil, headerFields: nil)!
    return (resp, Data())
  }

  // MARK: - Response helpers
  static func response(_ request: URLRequest, status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url ?? URL(string: "about:blank")!,
      statusCode: status,
      httpVersion: nil,
      headerFields: headers
    )!
  }

  static func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [])
  }
}
