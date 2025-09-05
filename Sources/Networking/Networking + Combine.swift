import Foundation
import Combine

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
public extension Networking {
  
  /// Get a publisher that receive response from a network request
  /// - Parameter request: the configured request object
  /// - Returns: Return a publisher that manage data type and error
  func publisher(
    from request: Request
  ) -> AnyPublisher<Data, Error> {
    do {
      let urlRequest = try request.urlRequest()
      return session
        .dataTaskPublisher(for: urlRequest)
        .tryMap { data, response in
          guard
            let response = response as? HTTPURLResponse
          else {
            throw NetworkError.transportError
          }
          
          let statusCode = HTTPStatus(response.statusCode)
          
          if case .success = statusCode {
            return data
          } else {
            throw NetworkError.httpSeverSideError(data, statusCode: statusCode)
          }
        }
        .eraseToAnyPublisher()
    } catch {
      return Fail(error: error)
        .eraseToAnyPublisher()
    }
  }
  
  /// Get a publisher that receive response from a network request
  /// - Parameters:
  ///   - type: The Decodable type of object we want to cast from the response data
  ///   - request: the configured request object
  /// - Returns: Return a publisher that manage desired data type and error
  func publisher<T>(
    for type: T.Type,
    from request: Request
  ) -> AnyPublisher<T, Error> where T: Decodable {
    do {
      let urlRequest = try request.urlRequest()
      return session
        .dataTaskPublisher(for: urlRequest)
        .tryMap { data, response in
          guard
            let response = response as? HTTPURLResponse
          else {
            throw NetworkError.transportError
          }
          
          let statusCode = HTTPStatus(response.statusCode)
          
          if case .success = statusCode {
            return data
          } else {
            throw NetworkError.httpSeverSideError(data, statusCode: statusCode)
          }
        }
        .decode(type: T.self, decoder: JSONDecoder())
        .eraseToAnyPublisher()
    } catch {
      return Fail(error: error)
        .eraseToAnyPublisher()
    }
  }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
extension Networking {
  /*
   Note: This function has the same purpose with publisher(from:) function.
   It is just a practice of consuming Combine with a call back function
   So I just keep this function here as a reference,
   not visible for end library user
   */
  func getPublisher<T>(
    from request: Request
  ) -> AnyPublisher<T, Error> where T: Decodable {
    return Deferred {
      Future { [unowned self] promise in
        Task {
          do {
            let result = try await self.get(T.self, from: request)
            promise(.success(result))
          } catch {
            promise(.failure(error))
          }
        }
      }
    }
    .eraseToAnyPublisher()
  }
}
