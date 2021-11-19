import Foundation

// MARK: - Stabdard functions with callbacks
extension Networking {
  
  /// Call a HTTP request. All the error handlers will stop the function immidiately
  /// - Parameters:
  ///   - method: HTTP method, `POST` in default
  ///   - url: plain string of the url.
  ///   - authorization: the authorization method, such as bearer token for example
  ///   - params: http request body's parameters.
  ///   - handler: Handling when completion, included success and failure
  public func sendRequest(
    _ request: Request,
    completion handler: @escaping NetworkHandler
  ) {
    do {
      let request = try request.request()
      
      session.dataTask(with: request) { data, response, error in
        
        // handle transport error
        if let error = error {
          DispatchQueue.main.async {
            return handler(.failure(error))
          }
        }
        
        guard
          let response = response as? HTTPURLResponse,
          let responseBody = data
        else {
          DispatchQueue.main.async {
            handler(.failure(NetworkError.transportError))
          }
          return
        }
        
        let statusCode = HTTPStatus(response.statusCode)
        
        if case .success = statusCode {
          /// success handling
          DispatchQueue.main.async {
            handler(.success(responseBody))
          }
        } else {
          /// HTTP server-side error handling
          // Printout the information
          if let responseString = String(bytes: responseBody, encoding: .utf8) {
            debugPrint(responseString)
          } else {
            // Otherwise print a hex dump of the body.
            debugPrint("😳 hex dump of the body")
            debugPrint(responseBody as NSData)
          }
          
          // return with error handler
          DispatchQueue.main.async {
            handler(
              .failure(
                NetworkError
                  .httpSeverSideError(responseBody, statusCode: statusCode)
              )
            )
          }
          return
        }
      }.resume()
      
    } catch {
      return handler(.failure(error))
    }
  }
  
  /// Call a HTTP request with expected return JSON object.
  /// All the error handlers will stop the function immidiately
  /// - Parameters:
  ///   - method: HTTP method, `POST` in default
  ///   - url: plain string of the url.
  ///   - authorization: the authorization method, such as bearer token for example
  ///   - params: http request body's parameters.
  ///   - handler: Handling when completion, included success and failure
  public func getObjectViaRequest<ObjectType: Codable>(
    _ request: Request,
    completion handler: @escaping NetworkGenericHandler<ObjectType>
  ) {
    do {
      
      let request = try request.request()
      
      session.dataTask(with: request) { data, response, error in
        
        // handle transport error
        if let error = error {
          DispatchQueue.main.async {
            return handler(.failure(error))
          }
        }
        
        guard
          let response = response as? HTTPURLResponse,
          let responseBody = data else {
            DispatchQueue.main.async {
              handler(.failure(NetworkError.transportError))
            }
            return
          }
        
        let statusCode = HTTPStatus(response.statusCode)
        
        if case .success = statusCode {
          /// success handling
          DispatchQueue.main.async {
            //handler(.success(responseBody))
            do {
              let object = try JSONDecoder()
                .decode(ObjectType.self, from: responseBody)
              handler(.success(object))
            } catch {
              handler(.failure(error))
            }
          }
        } else {
          /// HTTP server-side error handling
          // Printout the information
          if let responseString = String(bytes: responseBody, encoding: .utf8) {
            debugPrint(responseString)
          } else {
            // Otherwise print a hex dump of the body.
            debugPrint("😳 hex dump of the body")
            debugPrint(responseBody as NSData)
          }
          
          // return with error handler
          DispatchQueue.main.async {
            handler(
              .failure(
                NetworkError
                  .httpSeverSideError(responseBody, statusCode: statusCode)
              )
            )
          }
          return
        }
      }.resume()
      
    } catch {
      return handler(.failure(error))
    }
  }
}
