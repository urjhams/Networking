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

  // MARK: - OAuth 1.0 Implementation
  private func generateOAuth1Header(
    consumerKey: String,
    consumerSecret: String,
    token: String?,
    tokenSecret: String?,
    signature: Networking.OAuth1Signature,
    httpMethod: String,
    url: String,
    parameters: [String: Sendable?]?
  ) throws -> String {
    let timestamp = String(Int(Date().timeIntervalSince1970))
    let nonce = UUID().uuidString

    var oauthParams: [String: String] = [
      "oauth_consumer_key": consumerKey,
      "oauth_nonce": nonce,
      "oauth_signature_method": signature.rawValue,
      "oauth_timestamp": timestamp,
      "oauth_version": "1.0",
    ]

    if let token = token {
      oauthParams["oauth_token"] = token
    }

    // Generate signature base string
    let signatureBaseString = try generateOAuth1SignatureBaseString(
      httpMethod: httpMethod,
      url: url,
      oauthParams: oauthParams,
      parameters: parameters
    )

    // Generate signing key
    let signingKey = "\(consumerSecret.percentEncoded())&\(tokenSecret?.percentEncoded() ?? "")"

    // Generate signature
    let oauthSignature = try generateOAuth1Signature(
      baseString: signatureBaseString,
      signingKey: signingKey,
      method: signature
    )

    oauthParams["oauth_signature"] = oauthSignature

    // Build authorization header
    let sortedParams = oauthParams.sorted { $0.key < $1.key }
    let paramString =
      sortedParams
      .map { "\($0.key)=\"\($0.value.percentEncoded())\"" }
      .joined(separator: ", ")

    return "OAuth \(paramString)"
  }

  // MARK: - Hawk Authentication Implementation
  private func generateHawkHeader(
    id: String,
    key: String,
    algorithm: Networking.HawkAlgorithm,
    httpMethod: String,
    url: String,
    host: String,
    port: Int
  ) throws -> String {
    let timestamp = String(Int(Date().timeIntervalSince1970))
    let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    guard let urlComponents = URLComponents(string: url) else {
      throw NetworkError.badUrl
    }

    let resource =
      urlComponents.path + (urlComponents.query?.isEmpty == false ? "?\(urlComponents.query!)" : "")

    // Create normalized request string
    let normalizedString =
      [
        "hawk.1.header",
        timestamp,
        nonce,
        httpMethod.uppercased(),
        resource,
        host.lowercased(),
        String(port),
        "",  // hash (empty for now)
        "",  // ext (empty)
      ].joined(separator: "\n") + "\n"

    // Generate MAC
    let mac = try generateHawkMAC(
      normalizedString: normalizedString, key: key, algorithm: algorithm)

    return "Hawk id=\"\(id)\", ts=\"\(timestamp)\", nonce=\"\(nonce)\", mac=\"\(mac)\""
  }

  // MARK: - AWS Signature V4 Implementation
  private func generateAWSSignatureHeaders(
    accessKey: String,
    secretKey: String,
    region: String,
    service: String,
    sessionToken: String?,
    httpMethod: String,
    url: String,
    headers: [String: String]
  ) throws -> [String: String] {
    let date = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
    let amzDate = dateFormatter.string(from: date)

    dateFormatter.dateFormat = "yyyyMMdd"
    let dateStamp = dateFormatter.string(from: date)

    var awsHeaders = headers
    awsHeaders["Host"] = URL(string: url)?.host ?? ""
    awsHeaders["X-Amz-Date"] = amzDate

    if let sessionToken = sessionToken {
      awsHeaders["X-Amz-Security-Token"] = sessionToken
    }

    // Create canonical request
    let canonicalRequest = try createAWSCanonicalRequest(
      httpMethod: httpMethod,
      url: url,
      headers: awsHeaders
    )

    // Create string to sign
    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      credentialScope,
      Data(SHA256.hash(data: canonicalRequest.data(using: .utf8)!)).hexString,
    ].joined(separator: "\n")

    // Calculate signature
    let signature = try calculateAWSSignature(
      stringToSign: stringToSign,
      secretKey: secretKey,
      region: region,
      service: service,
      dateStamp: dateStamp
    )

    // Create authorization header
    let authorization =
      "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(getSignedHeaders(awsHeaders)), Signature=\(signature)"

    awsHeaders["Authorization"] = authorization
    return awsHeaders
  }

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
    let oauth1Header = try generateOAuth1Header(
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
    let hawkHeader = try generateHawkHeader(
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
    let awsHeaders = try generateAWSSignatureHeaders(
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

  // MARK: - AWS Helper Methods
  private func createAWSCanonicalRequest(
    httpMethod: String,
    url: String,
    headers: [String: String]
  ) throws -> String {
    guard let urlComponents = URLComponents(string: url) else {
      throw NetworkError.badUrl
    }

    let canonicalUri = urlComponents.path.isEmpty ? "/" : urlComponents.path
    let canonicalQueryString =
      urlComponents.queryItems?.sorted { $0.name < $1.name }
      .map { "\($0.name.awsEncoded())=\($0.value?.awsEncoded() ?? "")" }
      .joined(separator: "&") ?? ""

    let sortedHeaders = headers.sorted { $0.key.lowercased() < $1.key.lowercased() }
    let canonicalHeaders =
      sortedHeaders
      .map { "\($0.key.lowercased()):\($0.value.trimmingCharacters(in: .whitespacesAndNewlines))" }
      .joined(separator: "\n") + "\n"

    let signedHeaders = getSignedHeaders(headers)
    let payloadHash = Data(SHA256.hash(data: Data())).hexString

    return [
      httpMethod.uppercased(),
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].joined(separator: "\n")
  }

  private func calculateAWSSignature(
    stringToSign: String,
    secretKey: String,
    region: String,
    service: String,
    dateStamp: String
  ) throws -> String {
    let kDate = HMAC<SHA256>.authenticationCode(
      for: dateStamp.data(using: .utf8)!,
      using: SymmetricKey(data: "AWS4\(secretKey)".data(using: .utf8)!)
    )

    let kRegion = HMAC<SHA256>.authenticationCode(
      for: region.data(using: .utf8)!,
      using: SymmetricKey(data: kDate)
    )

    let kService = HMAC<SHA256>.authenticationCode(
      for: service.data(using: .utf8)!,
      using: SymmetricKey(data: kRegion)
    )

    let kSigning = HMAC<SHA256>.authenticationCode(
      for: "aws4_request".data(using: .utf8)!,
      using: SymmetricKey(data: kService)
    )

    let signature = HMAC<SHA256>.authenticationCode(
      for: stringToSign.data(using: .utf8)!,
      using: SymmetricKey(data: kSigning)
    )

    return Data(signature).hexString
  }

  private func getSignedHeaders(_ headers: [String: String]) -> String {
    return headers.keys
      .map { $0.lowercased() }
      .sorted()
      .joined(separator: ";")
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
