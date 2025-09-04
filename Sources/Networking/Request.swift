import Foundation
import CryptoKit

/// A Sendable-conforming type that can hold various parameter values
public enum ParameterValue: Sendable {
  case string(String)
  case int(Int)
  case double(Double) 
  case bool(Bool)
  case null
  
  var anyValue: Any {
    switch self {
    case .string(let value): return value
    case .int(let value): return value
    case .double(let value): return value
    case .bool(let value): return value
    case .null: return NSNull()
    }
  }
}

public protocol BaseRequest {
  var baseURL: String { get set }
  var method: Networking.Method { get set }
  var timeOut: TimeInterval { get set }
  var authorization: Networking.Authorization? { get set }
  var cachePolicy: URLRequest.CachePolicy { get set }
  var parameters: [String : ParameterValue?]? { get set }
  
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
    parameters: [String : ParameterValue?]? = nil
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
  
  private func generateDigestResponse(
    username: String,
    password: String,
    realm: String,
    nonce: String,
    uri: String,
    method: String,
    qop: String? = nil,
    nc: String? = nil,
    cnonce: String? = nil
  ) throws -> String {
    // HA1 = MD5(username:realm:password)
    let ha1String = "\(username):\(realm):\(password)"
    let ha1Data = ha1String.data(using: .utf8) ?? Data()
    let ha1Hash = Insecure.MD5.hash(data: ha1Data)
    let ha1 = ha1Hash.map { String(format: "%02hhx", $0) }.joined()
    
    // HA2 = MD5(method:uri)
    let ha2String = "\(method):\(uri)"
    let ha2Data = ha2String.data(using: .utf8) ?? Data()
    let ha2Hash = Insecure.MD5.hash(data: ha2Data)
    let ha2 = ha2Hash.map { String(format: "%02hhx", $0) }.joined()
    
    // Response calculation
    let responseString: String
    if let qop = qop, let nc = nc, let cnonce = cnonce {
      // Response = MD5(HA1:nonce:nc:cnonce:qop:HA2)
      responseString = "\(ha1):\(nonce):\(nc):\(cnonce):\(qop):\(ha2)"
    } else {
      // Response = MD5(HA1:nonce:HA2)
      responseString = "\(ha1):\(nonce):\(ha2)"
    }
    
    let responseData = responseString.data(using: .utf8) ?? Data()
    let responseHash = Insecure.MD5.hash(data: responseData)
    return responseHash.map { String(format: "%02hhx", $0) }.joined()
  }
  
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
      case .digestAuth(let username, let password, let realm, let nonce, let uri, let qop, let nc, let cnonce):
        let response = try generateDigestResponse(
          username: username,
          password: password,
          realm: realm,
          nonce: nonce,
          uri: uri,
          method: method.rawValue,
          qop: qop,
          nc: nc,
          cnonce: cnonce
        )
        
        var digestHeader = "Digest username=\"\(username)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\", response=\"\(response)\""
        
        if let qop = qop, let nc = nc, let cnonce = cnonce {
          digestHeader += ", qop=\(qop), nc=\(nc), cnonce=\"\(cnonce)\""
        }
        
        request.setValue(digestHeader, forHTTPHeaderField: "Authorization")
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
            configParameters = [key: ParameterValue.string(value)]
          } else {
            configParameters![key] = ParameterValue.string(value)
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
      let anyParams = parameters.compactMapValues { $0?.anyValue }
      guard
        let json = try? JSONSerialization.data(withJSONObject: anyParams, options: [])
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
        URLQueryItem(name: key, value: String(describing: value?.anyValue ?? ""))
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
  
  public var parameters: [String : ParameterValue?]? = nil
  
  public var timeOut: TimeInterval = 60.0
  
  public var authorization: Networking.Authorization? = nil
  
  public required init() { }
}
