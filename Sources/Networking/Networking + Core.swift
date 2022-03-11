import Foundation

/// convenience extension for debugging Codable object
public extension CustomStringConvertible where Self: Codable {
  var description: String {
    var description = "\n \(type(of: self)) \n"
    let mirror = Mirror(reflecting: self)
    for child in mirror.children {
      if let propertyName = child.label {
        description += "\(propertyName): \(child.value)\n"
      }
    }
    return description
  }
}

extension URLSession: @unchecked Sendable {}

public final class Networking: Sendable {
  
  /// shared instance of Network class
  public static let shared = Networking()
  
  internal let session = URLSession.shared
  
  /// network handle closure
  public typealias NetworkHandler = (Result<Data, Error>) -> ()
  
  public typealias GenericResult<T: Codable> = Result<T, Error>
  
  // network handle generic closure
  public typealias NetworkGenericHandler<T: Codable> = (GenericResult<T>) -> ()
  
  /// private init to avoid unexpected instances allocate
  private init() {}
  
  public enum Method: String {
    case `get` = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
    case patch = "PATCH"
  }
  
  public enum NetworkError: Error {
    case badUrl
    case transportError
    case httpSeverSideError(Data, statusCode: HTTPStatus)
    case badRequestParameters([String: Any?])
    case jsonFormatError
    case downloadServerSideError(statusCode: HTTPStatus)
    case badRequestAuthorization
  }
  
  public enum Authorization {
    //TODO: support digestAuth
    // https://developer.apple.com/documentation/foundation/url_loading_system/handling_an_authentication_challenge
    // TODO: support OAuth 1.0, oAuth2, hawAuth, AWSSignature
    case basicAuth(userName: String, password: String)
    case bearerToken(token: String?)
    case apiKey(key: String, value: String)
  }
  
  
  /// Possible status code, will get raw value as 0 for the `unknown` case
  /// - 1xxs – `Informational responses`: The server is thinking through the request.
  /// - 2xxs – `Success`: The request was successfully completed
  /// and the server gave the browser the expected response.
  /// - 3xxs – `Redirection`: You got redirected somewhere else.
  /// The request was received, but there’s a redirect of some kind.
  /// - 4xxs – `Client errors`: Page not found. The site or page couldn’t be reached.
  /// (The request was made, but the page isn’t valid —
  /// this is an error on the website’s side of the conversation and often
  /// appears when a page doesn’t exist on the site.)
  /// - 5xxs – `Server errors`: Failure. A valid request was made
  /// by the client but the server failed to complete the request.
  public enum HTTPStatus: Int {
    case unknown
    
    case success = 200
    
    case PermanentRedirect = 301
    case TemporaryRedirect = 302
    
    case badRequest = 400
    case notAuthorized = 401
    case forbidden = 403
    case notFound = 404
    
    case internalServerError = 500
    case serviceUnavailable = 503
    
    public init(_ code: Int) {
      self = HTTPStatus.init(rawValue: code) ?? .unknown
    }
  }
}

extension Networking.NetworkError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .badUrl:
      return "⛔️ This seem not a vail url."
    case .transportError:
      return "⛔️ There is a transport error."
    case .httpSeverSideError( _,let statusCode):
      let code = statusCode.rawValue
      return "⛔️ There is a http server error with status code \(code)."
    case .badRequestParameters(let parameters):
      return "⛔️ this parameter set is invalid, check it again \n\(parameters)."
    case .jsonFormatError:
      return "⛔️ Failed in trying to decode the response body to a JSON data."
    case .downloadServerSideError(let statusCode):
      let code = statusCode.rawValue
      return "⛔️ There is a http server error with status code \(code)."
    case .badRequestAuthorization:
      return "⛔️ There is a problem with the request authorization header"
    }
  }
}

public protocol BaseRequest {
  var baseURL: String { get set }
  var method: Networking.Method { get set }
  var timeOut: TimeInterval { get set }
  var authorization: Networking.Authorization? { get set }
  var cachePolicy: URLRequest.CachePolicy { get set }
  var parameters: [String : Any?]? { get set }
  
  init()
}

public extension BaseRequest {
  typealias Method = Networking.Method
  typealias NetworkError = Networking.NetworkError
  typealias Authorization = Networking.Authorization
  
  /// default init
  init(
    from encodedUrl: String,
    as method: Method = .post,
    timeout: TimeInterval = 10.0,
    authorization: Authorization? = nil,
    cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
    parameters: [String : Any?]? = nil
  ) {
    self.init()
    self.baseURL = encodedUrl
    self.method = method
    self.timeOut = timeout
    self.authorization = authorization
    self.cachePolicy = cachePolicy
    
    self.parameters = parameters
  }
}

public extension BaseRequest {
  
  func urlRequest() throws -> URLRequest {
    // encode url (to encode spaces for example)
    guard
      let encodedUrl = self
        .baseURL
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      throw NetworkError.badUrl
    }
    
    guard let url = URL(string: encodedUrl) else {
      // bad url
      throw NetworkError.badUrl
    }
    
    var request = URLRequest(
      url: url,
      cachePolicy: cachePolicy,
      timeoutInterval: timeOut
    )
    
    request.httpMethod = method.rawValue
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    var configParameters = parameters
    
    // add Authorization information if has
    if let authorization = authorization {
      switch authorization {
      case .basicAuth(let username, let password):
        let authString = "\(username):\(password)"
        guard let data = authString.data(using: .utf8) else {
          throw NetworkError.badRequestAuthorization
        }
        let base64 = data.base64EncodedString()
        request.setValue(
          "Basic \(base64)",
          forHTTPHeaderField: "Authorization"
        )
      case .bearerToken(let token):
        guard let bearerToken = token else {
          throw NetworkError.badRequestAuthorization
        }
        request.setValue(
          "Bearer \(bearerToken)",
          forHTTPHeaderField: "Authorization"
        )
      case .apiKey(let key, let value):
        if case .get = method {
          if configParameters == nil {
            configParameters = [key: value]
          } else {
            configParameters![key] = value
          }
        } else {
          request.setValue(value, forHTTPHeaderField: key)
        }
      }
    }
    
    guard let parameters = configParameters else {
      return request
    }
    
    // only put parameter in HTTP body of a POST request,
    // for GET, add directly to the url
    switch method {
    case .post, .put, .patch:
      guard
        let json = try? JSONSerialization
          .data(withJSONObject: parameters, options: [])
      else {
        throw NetworkError.badRequestParameters(parameters)
      }
      request.httpBody = json
    case .get, .delete:
      guard var finalUrl = URLComponents(string: encodedUrl) else {
        throw NetworkError.badUrl
      }
      
      finalUrl.queryItems = parameters.map { key, value in
        // in case value is nil, replace by blank space instead
        URLQueryItem(name: key, value: String(describing: value ?? ""))
      }
      
      finalUrl.percentEncodedQuery = finalUrl
        .percentEncodedQuery?
        .replacingOccurrences(of: "+", with: "%2B")
      
      // re-assign the url with parameter components to the request
      request.url = finalUrl.url
    }
    
    return request
  }
}

public class Request: BaseRequest {
  public var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
  
  public var baseURL: String = ""
  
  public var method: Networking.Method = .post
  
  public var parameters: [String : Any?]? = nil
  
  public var timeOut: TimeInterval = 60.0
  
  public var authorization: Networking.Authorization? = nil
  
  public required init() { }
}
