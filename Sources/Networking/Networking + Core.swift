import Foundation

/// convenience extension for debugging Decodable object
public extension CustomStringConvertible where Self: Decodable {
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

public actor Networking {
  
  /// shared instance of Network class
  public static let shared = Networking()
  
  internal var session = URLSession.shared
  
  public func set(_ session: URLSession = .shared) {
    self.session = session
  }
  
  /// network handle closure
  public typealias NetworkHandler = @Sendable (Result<Data, Error>) -> ()
  
  public typealias GenericResult<T: Decodable> = Result<T, Error>
  
  // network handle generic closure
  public typealias NetworkGenericHandler<T: Decodable> = @Sendable (GenericResult<T>) -> ()
  
  /// private init to avoid unexpected instances allocate
  private init() {}
  
  public enum Method: String {
    case `get` = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
    case patch = "PATCH"
  }
  
  public enum NetworkError: Error, Equatable, Sendable {
    case badUrl
    case transportError
    case httpSeverSideError(Data, statusCode: HTTPStatus)
    case badRequestParameters(String)
    case jsonFormatError
    case downloadServerSideError(statusCode: HTTPStatus)
    case badRequestAuthorization
    case unknown
    
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
      return switch (rhs, lhs) {
      case (.badUrl, .badUrl),
        (.transportError, .transportError),
        (.jsonFormatError, .jsonFormatError),
        (.badRequestAuthorization, .badRequestAuthorization),
        (.unknown, .unknown):
        true
      case (.httpSeverSideError(let data1, let status1), .httpSeverSideError(let data2, let status2)):
        data1 == data2 && status1 == status2
      case (.badRequestParameters(let p1), .badRequestParameters(let p2)):
        p1 == p2
      case (.downloadServerSideError(let status1), .downloadServerSideError(let status2)):
        status1 == status2
      default:
        false
      }
    }
  }
  
  public enum Authorization {
    // https://developer.apple.com/documentation/foundation/url_loading_system/handling_an_authentication_challenge
    // TODO: support OAuth 1.0, oAuth2, hawAuth, AWSSignature
    case basicAuth(userName: String, password: String)
    case digestAuth(userName: String, password: String, realm: String, nonce: String, uri: String, qop: String? = nil, nc: String? = nil, cnonce: String? = nil)
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
  public enum HTTPStatus: Int, Sendable {
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
    case .unknown:
      return "⛔️ unknown network error"
    }
  }
}
