import Foundation

// MARK: Concurrency
@available(swift 5.5)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
extension URLSession {
  /// Apply data task with async/ await for the lower OS that still support concurency
  ///
  /// Even though Concurency is available from iOS 13 now, it's a Language feature.
  /// Apple did not provide any async APIs for the SDKs under 15+ like URLSession.
  /// So we use a trick that wrapping the standard function (with callbacks) in
  /// `withCheckedThrowingContinuation` to use async / await to it.
  /// Concurency is now available for iOS 13, etc. However, the other Apple's SDK like
  /// - Parameter request: the fully configured request
  /// - Returns: the data and response like `URLSession.shared.data(for:)`  function
  /// in iOS 15+
  @available(
    iOS,
    deprecated: 15.0,
    message: "Deprecated! Use data(for request:, delegate:) instead"
  )
  @available(
    tvOS,
    deprecated: 15.0,
    message: "Deprecated! Use data(for request:, delegate:) instead"
  )
  @available(
    macOS,
    deprecated: 12.0,
    message: "Deprecated! Use data(for request:, delegate:) instead"
  )
  @available(
    watchOS,
    deprecated: 8.0,
    message: "Deprecated! Use data(for request:, delegate:) instead"
  )
  func data(from request: URLRequest) async throws -> (Data, URLResponse) {
    // Wrap the standard callback api in withCheckedThrowingContinuation
    try await withCheckedThrowingContinuation { continuation in
      let task = dataTask(with: request) { data, response, error in
        guard let data = data, let response = response else {
          let error = error ?? Networking.NetworkError.transportError
          return continuation.resume(throwing: error)
        }

        continuation.resume(returning: (data, response))
      }

      task.resume()
    }
  }
}

@available(swift 5.5)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
extension Networking {

  /// Call a HTTP request. All the error handlers will stop the function immediately
  /// - Parameters:
  ///   - request: the configured request object
  /// - Returns: the response data and information
  @discardableResult
  public func sendRequest(
    _ request: Request,
    session: URLSession = .shared
  ) async throws -> (Data, HTTPURLResponse) {

    let urlRequest = try request.urlRequest()

    // try to get data from request
    let (data, response): (Data, URLResponse)
    if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
      (data, response) = try await session.data(for: urlRequest)
    } else {
      (data, response) = try await session.data(from: urlRequest)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw NetworkError.transportError
    }

    guard HTTPStatus(httpResponse.statusCode) == .success else {
      let statusCode = HTTPStatus(httpResponse.statusCode)
      throw NetworkError.httpSeverSideError(data, statusCode: statusCode)
    }

    return (data, httpResponse)
  }

  /// Call a HTTP request. All the error handlers will stop the function immediately
  /// - Parameters:
  ///   - request: the configured request object
  /// - Returns: the response data or error
  public func send(
    _ request: Request,
    session: URLSession = .shared
  ) async -> Result<Data, Networking.NetworkError> {
    do {
      let response = try await sendRequest(request, session: session)
      let status = HTTPStatus(response.1.statusCode)
      switch status {
      case .success:
        return .success(response.0)
      case .unknown:
        return .failure(.unknown)
      default:
        return .failure(.httpSeverSideError(response.0, statusCode: status))
      }
    } catch {
      return .failure(.unknown)
    }
  }

  /// Get the expected JSON - Decodable object via a HTTP request.
  /// - Parameters:
  ///   - objectType: The Decodable type of object we want to cast from the response data
  ///   - request: the configured request object
  /// - Returns: the expected JSON object.
  public func get<T>(
    _ objectType: T.Type,
    from request: Request,
    session: URLSession = .shared
  ) async throws -> T where T: Decodable {

    let urlRequest = try request.urlRequest()
    // try to get data from request
    let (data, response): (Data, URLResponse)
    if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
      (data, response) = try await session.data(for: urlRequest)
    } else {
      (data, response) = try await session.data(from: urlRequest)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw NetworkError.transportError
    }

    guard HTTPStatus(httpResponse.statusCode) == .success else {
      let statusCode = HTTPStatus(httpResponse.statusCode)
      throw NetworkError.httpSeverSideError(data, statusCode: statusCode)
    }

    guard let object = try? JSONDecoder().decode(objectType.self, from: data)
    else {
      throw NetworkError.jsonFormatError
    }

    return object
  }

  /// Get one of multiple possible Decodable types from a single HTTP response.
  ///
  /// Tries to decode the response body into each provided type in order and
  /// returns the first successful result. If none of the types match the
  /// payload, the function throws `Networking.NetworkError.jsonFormatError`.
  ///
  /// - Parameters:
  ///   - possibleType: Ordered list of candidate `Decodable` types. The function
  ///     attempts decoding in this order and returns on the first match.
  ///   - request: Fully configured `Request` describing the HTTP call.
  ///   - session: `URLSession` used to perform the request. Defaults to `.shared`.
  /// - Returns: The decoded value as `Decodable`. Cast the returned value to your
  ///   expected concrete type (e.g. `as? User` or `as? ErrorEnvelope`).
  /// - Throws: `Networking.NetworkError.badUrl` when building the request fails;
  ///   `Networking.NetworkError.transportError` when response is missing/invalid;
  ///   `Networking.NetworkError.httpSeverSideError(_, statusCode:)` for non-2xx;
  ///   `Networking.NetworkError.jsonFormatError` when no provided type decodes.
  ///
  /// Example:
  /// ```swift
  /// struct User: Decodable, Sendable { let id: Int }
  /// struct ErrorEnvelope: Decodable { let message: String }
  /// let value = try await networking.get(
  ///   possibleType: [User.self, ErrorEnvelope.self],
  ///   from: request
  /// )
  /// if let user = value as? User {
  ///   // handle success
  /// } else if let serverError = value as? ErrorEnvelope {
  ///   // handle API error payload encoded as JSON
  /// }
  /// ```
  public func get(
    possibleType: [ConcurencyDecodable.Type],
    from request: Request,
    session: URLSession = .shared
  ) async throws -> ConcurencyDecodable {

    let urlRequest = try request.urlRequest()

    // try to get data from request
    let (data, response): (Data, URLResponse)
    if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, *) {
      (data, response) = try await session.data(for: urlRequest)
    } else {
      (data, response) = try await session.data(from: urlRequest)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw NetworkError.transportError
    }

    guard HTTPStatus(httpResponse.statusCode) == .success else {
      let statusCode = HTTPStatus(httpResponse.statusCode)
      throw NetworkError.httpSeverSideError(data, statusCode: statusCode)
    }

    let decoder = JSONDecoder()
    for objectType in possibleType {
      if let decoded = try? decoder.decode(objectType, from: data) {
        return decoded
      }
    }

    throw NetworkError.jsonFormatError
  }

  /// Safety get the expected JSON - Decodable object via a HTTP request.
  /// - Parameters:
  ///   - objectType: The Decodable type of object we want to cast from the response data
  ///   - request: the configured request object
  /// - Returns: the expected JSON object or Error
  public func getObj<T>(
    _ objectType: T.Type,
    from request: Request,
    session: URLSession = .shared
  ) async -> Result<T, Networking.NetworkError> where T: Decodable {
    do {
      let object = try await get(objectType, from: request, session: session)
      return .success(object)
    } catch {
      return .failure(.unknown)
    }
  }
}
