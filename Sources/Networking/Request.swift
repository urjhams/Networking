import CommonCrypto
import CryptoKit
import Foundation

public protocol BaseRequest {
  var baseURL: String { get set }
  var method: Networking.Method { get set }
  var timeOut: TimeInterval { get set }
  var authorization: Networking.Authorization? { get set }
  var cachePolicy: URLRequest.CachePolicy { get set }
  var parameters: [String: Sendable?]? { get set }

  init()
}

extension BaseRequest {
  public typealias Method = Networking.Method
  public typealias NetworkError = Networking.NetworkError
  public typealias Authorization = Networking.Authorization

  /// default init
  public init(
    from encodedUrl: String,
    as method: Method = .post,
    timeout: TimeInterval = 10.0,
    authorization: Authorization? = nil,
    cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
    parameters: [String: (any Sendable)?]? = nil
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

      return digest.map { String(format: "%02hhx", $0) }.joined()
    case .plain(let plain):
      return plain
    }
  }

}

extension BaseRequest {

  // MARK: - OAuth 1.0 Helper Methods
  private func generateOAuth1SignatureBaseString(
    httpMethod: String,
    url: String,
    oauthParams: [String: String],
    parameters: [String: Sendable?]?
  ) throws -> String {
    guard let urlComponents = URLComponents(string: url) else {
      throw NetworkError.badUrl
    }

    let baseUrl =
      "\(urlComponents.scheme ?? "https")://\(urlComponents.host ?? "")\(urlComponents.path)"

    var allParams: [String: String] = oauthParams

    // Add query parameters
    urlComponents.queryItems?.forEach { item in
      allParams[item.name] = item.value ?? ""
    }

    // Add body parameters (for POST/PUT)
    parameters?.forEach { key, value in
      if let paramValue = value {
        allParams[key] = String(describing: paramValue)
      }
    }

    // Sort and encode parameters
    let sortedParams = allParams.sorted { $0.key < $1.key }
    let paramString =
      sortedParams
      .map { "\($0.key.percentEncoded())=\($0.value.percentEncoded())" }
      .joined(separator: "&")

    return [
      httpMethod.uppercased().percentEncoded(),
      baseUrl.percentEncoded(),
      paramString.percentEncoded(),
    ].joined(separator: "&")
  }

  private func generateOAuth1Signature(
    baseString: String,
    signingKey: String,
    method: Networking.OAuth1Signature
  ) throws -> String {
    switch method {
    case .hmacSha1:
      let keyData = signingKey.data(using: .utf8)!
      let baseData = baseString.data(using: .utf8)!
      let signature = HMAC<Insecure.SHA1>.authenticationCode(
        for: baseData, using: SymmetricKey(data: keyData))
      return Data(signature).base64EncodedString()

    case .hmacSha256:
      let keyData = signingKey.data(using: .utf8)!
      let baseData = baseString.data(using: .utf8)!
      let signature = HMAC<SHA256>.authenticationCode(
        for: baseData, using: SymmetricKey(data: keyData))
      return Data(signature).base64EncodedString()

    case .plaintext:
      return signingKey
    }
  }

  // MARK: - Hawk Helper Methods
  private func generateHawkMAC(
    normalizedString: String,
    key: String,
    algorithm: Networking.HawkAlgorithm
  ) throws -> String {
    let keyData = key.data(using: .utf8)!
    let stringData = normalizedString.data(using: .utf8)!

    switch algorithm {
    case .sha1:
      let mac = HMAC<Insecure.SHA1>.authenticationCode(
        for: stringData, using: SymmetricKey(data: keyData))
      return Data(mac).base64EncodedString()

    case .sha256:
      let mac = HMAC<SHA256>.authenticationCode(for: stringData, using: SymmetricKey(data: keyData))
      return Data(mac).base64EncodedString()
    }
  }

  // MARK: - Authorization Helper Methods
  private func configureBasicAuth(
    _ request: inout URLRequest,
    username: String,
    password: String
  ) throws {
    let authString = "\(username):\(password)"
    guard let data = authString.data(using: .utf8) else {
      throw NetworkError.badRequestAuthorization
    }
    let base64 = data.base64EncodedString()
    request.setValue(
      "Basic \(base64)",
      forHTTPHeaderField: "Authorization"
    )
  }

  private func configureDigestAuth(
    _ request: inout URLRequest,
    username: String,
    password: String,
    realm: String,
    nonce: String,
    uri: String,
    qop: String?,
    nc: String?,
    cnonce: String?
  ) throws {
    let response = try AuthorizeMethodGenerator.shared.generateDigestResponse(
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
    
    var digestHeader = "Digest username=\"\(username)\"," +
      " realm=\"\(realm)\"," +
      " nonce=\"\(nonce)\"," +
      " uri=\"\(uri)\"," +
      " response=\"\(response)\""

    if let qop = qop, let nc = nc, let cnonce = cnonce {
      digestHeader += ", qop=\(qop), nc=\(nc), cnonce=\"\(cnonce)\""
    }

    request.setValue(digestHeader, forHTTPHeaderField: "Authorization")
  }

  private func configureBearerToken(
    _ request: inout URLRequest,
    token: String?
  ) throws {
    guard let bearerToken = token else {
      throw NetworkError.badRequestAuthorization
    }
    request.setValue(
      "Bearer \(bearerToken)",
      forHTTPHeaderField: "Authorization"
    )
  }

  private func configureApiKey(
    _ request: inout URLRequest,
    key: String,
    value: String,
    configParameters: inout [String: Sendable?]?
  ) {
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

  private func configureOAuth1(
    _ request: inout URLRequest,
    consumerKey: String,
    consumerSecret: String,
    token: String?,
    tokenSecret: String?,
    signature: Networking.OAuth1Signature,
    encodedUrl: String,
    parameters: [String: Sendable?]?
  ) throws {
    let oauth1Header = try AuthorizeMethodGenerator.shared.generateOAuth1Header(
      consumerKey: consumerKey,
      consumerSecret: consumerSecret,
      token: token,
      tokenSecret: tokenSecret,
      signature: signature,
      httpMethod: method.rawValue,
      url: encodedUrl,
      parameters: parameters
    )
    request.setValue(oauth1Header, forHTTPHeaderField: "Authorization")
  }

  private func configureOAuth2(
    _ request: inout URLRequest,
    accessToken: String,
    tokenType: String
  ) {
    request.setValue("\(tokenType) \(accessToken)", forHTTPHeaderField: "Authorization")
  }

  private func configureHawk(
    _ request: inout URLRequest,
    id: String,
    key: String,
    algorithm: Networking.HawkAlgorithm,
    encodedUrl: String
  ) throws {
    let hawkHeader = try AuthorizeMethodGenerator.shared.generateHawkHeader(
      id: id,
      key: key,
      algorithm: algorithm,
      httpMethod: method.rawValue,
      url: encodedUrl,
      host: URL(string: encodedUrl)?.host ?? "",
      port: URL(string: encodedUrl)?.port ?? (encodedUrl.hasPrefix("https") ? 443 : 80)
    )
    request.setValue(hawkHeader, forHTTPHeaderField: "Authorization")
  }

  private func configureAWSSignature(
    _ request: inout URLRequest,
    accessKey: String,
    secretKey: String,
    region: String,
    service: String,
    sessionToken: String?,
    encodedUrl: String
  ) throws {
    let awsHeaders = try AuthorizeMethodGenerator.shared.generateAWSSignatureHeaders(
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      service: service,
      sessionToken: sessionToken,
      httpMethod: method.rawValue,
      url: encodedUrl,
      headers: request.allHTTPHeaderFields ?? [:]
    )
    for (key, value) in awsHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
  }


  public func urlRequest(singed signature: Signature? = nil) throws -> URLRequest {
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
        try configureBasicAuth(&request, username: username, password: password)
        
      case .digestAuth(
        let username, let password, let realm, let nonce, let uri, let qop, let nc, let cnonce):
        try configureDigestAuth(
          &request,
          username: username,
          password: password,
          realm: realm,
          nonce: nonce,
          uri: uri,
          qop: qop,
          nc: nc,
          cnonce: cnonce
        )
        
      case .bearerToken(let token):
        try configureBearerToken(&request, token: token)
        
      case .apiKey(let key, let value):
        configureApiKey(&request, key: key, value: value, configParameters: &configParameters)

      case .oauth1(let consumerKey, let consumerSecret, let token, let tokenSecret, let signature):
        try configureOAuth1(
          &request,
          consumerKey: consumerKey,
          consumerSecret: consumerSecret,
          token: token,
          tokenSecret: tokenSecret,
          signature: signature,
          encodedUrl: encodedUrl,
          parameters: configParameters
        )

      case .oauth2(let accessToken, let tokenType):
        configureOAuth2(&request, accessToken: accessToken, tokenType: tokenType)

      case .hawk(let id, let key, let algorithm):
        try configureHawk(
          &request,
          id: id,
          key: key,
          algorithm: algorithm,
          encodedUrl: encodedUrl
        )

      case .awsSignature(let accessKey, let secretKey, let region, let service, let sessionToken):
        try configureAWSSignature(
          &request,
          accessKey: accessKey,
          secretKey: secretKey,
          region: region,
          service: service,
          sessionToken: sessionToken,
          encodedUrl: encodedUrl
        )
      }
    }

    guard let parameters = configParameters else {
      return request
    }

    // only put parameter in HTTP body of a POST request,
    // for GET, add directly to the url
    switch method {
    case .post, .put, .patch:
      let anyParams = parameters.compactMapValues { $0 }
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

  public var parameters: [String: Sendable?]? = nil

  public var timeOut: TimeInterval = 60.0

  public var authorization: Networking.Authorization? = nil

  public required init() {}
}

// MARK: - String Extensions for Authentication
internal let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
extension String {
  func percentEncoded() -> String {
    let allowed = CharacterSet(charactersIn: chars)
    return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }

  func awsEncoded() -> String {
    let allowed = CharacterSet(charactersIn: chars)
    return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }
}

// MARK: - Data Extensions
extension Data {
  var hexString: String {
    return self.map { String(format: "%02hhx", $0) }.joined()
  }
}
