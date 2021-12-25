import Foundation

// MARK: Concurrency
@available(swift 5.5)
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
extension URLSession {
  /// Apply data task with async/ await for the lower OS that still support concurency
  ///
  /// Eventhough Concurency is avalable from iOS 13 now, it's a Language feature.
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
    message: "Decrpecated! Use data(for request:, delegate:) instead"
  )
  @available(
    tvOS,
    deprecated: 15.0,
    message: "Decrpecated! Use data(for request:, delegate:) instead"
  )
  @available(
    macOS,
    deprecated: 12.0,
    message: "Decrpecated! Use data(for request:, delegate:) instead"
  )
  @available(
    watchOS,
    deprecated: 8.0,
    message: "Decrpecated! Use data(for request:, delegate:) instead"
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
public extension Networking {
  
  /// Call a HTTP request. All the error handlers will stop the function immidiately
  /// - Parameters:
  ///   - request: the configured request object
  func sendRequest(
    _ request: Request
  ) async throws -> (Data, HTTPURLResponse) {
    
    let urlRequest = try request.urlRequest()
    
    // try to get data from request
    let (data, response): (Data, URLResponse)
    if #available(
      iOS 15.0,
      macOS 12.0,
      tvOS 15.0,
      watchOS 8.0,
      macCatalyst 15.0,
      *
    ) {
      (data, response) = try await URLSession.shared.data(for: urlRequest)
    } else {
      (data, response) = try await URLSession.shared.data(from: urlRequest)
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
  
  /// Get the expected JSON - codable object via a HTTP request.
  /// - Parameters:
  ///   - objectType: The codable type of object we want to cast from the response data
  ///   - request: the configured request object
  /// - Returns: the expected JSON object.
  func get<ObjectType: Codable>(
    _ objectType: ObjectType.Type,
    from request: Request
  ) async throws -> ObjectType {
    
    let urlRequest = try request.urlRequest()
    
    // try to get data from request
    let (data, response): (Data, URLResponse)
    if #available(
      iOS 15.0,
      macOS 12.0,
      tvOS 15.0,
      watchOS 8.0,
      macCatalyst 15.0,
      *
    ) {
      (data, response) = try await URLSession.shared.data(for: urlRequest)
    } else {
      (data, response) = try await URLSession.shared.data(from: urlRequest)
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw NetworkError.transportError
    }
    
    guard HTTPStatus(httpResponse.statusCode) == .success else {
      let statusCode = HTTPStatus(httpResponse.statusCode)
      throw NetworkError.httpSeverSideError(data, statusCode: statusCode)
    }
    
    guard let object = try? JSONDecoder()
            .decode(objectType.self, from: data)
    else {
      throw NetworkError.jsonFormatError
    }
    
    return object
  }
}
