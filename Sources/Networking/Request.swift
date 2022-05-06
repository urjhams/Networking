import Foundation
import CryptoKit

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

public enum Signature {
  case md5(String)
  case plain(String)
  
  var plain: String {
    switch self {
    case .md5(let secret):
      let digest = Insecure.MD5.hash(data: secret.data(using: .utf8) ?? Data())
      
      return digest.map{ String(format: "%02hhx", $0) }.joined()
    case .plain(let plain):
      return plain
    }
  }
  
}

public extension BaseRequest {
  
  func urlRequest(singed signature: Signature? = nil) throws -> URLRequest {
    // encode url (to encode spaces for example)
    guard
      var encodedUrl = self
        .baseURL
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    else {
      throw NetworkError.badUrl
    }
    
    if let signature = signature, case .md5(_) = signature {
      let signatureString = signature.plain
      encodedUrl = "\(encodedUrl)&signature=\(signatureString)"
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
    
    if case .plain(let keyword) = signature {
      request.setValue(keyword, forHTTPHeaderField: "Signature")
    }
    
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

public final class Request: BaseRequest, @unchecked Sendable {
  public var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
  
  public var baseURL: String = ""
  
  public var method: Networking.Method = .post
  
  public var parameters: [String : Any?]? = nil
  
  public var timeOut: TimeInterval = 60.0
  
  public var authorization: Networking.Authorization? = nil
  
  public required init() { }
}
