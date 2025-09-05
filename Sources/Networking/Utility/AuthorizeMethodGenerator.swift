import CommonCrypto
import CryptoKit
import Foundation

public final class AuthorizeMethodGenerator: @unchecked Sendable {
  public static let shared = AuthorizeMethodGenerator()
  
  private init() {}
  
  // MARK: - Digest Authentication
  public func generateDigestResponse(
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
  public func generateOAuth1Header(
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
  public func generateHawkHeader(
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
      throw Networking.NetworkError.badUrl
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
  public func generateAWSSignatureHeaders(
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
}

// MARK: - OAuth 1.0 Helper Methods
extension AuthorizeMethodGenerator {
  private func generateOAuth1SignatureBaseString(
    httpMethod: String,
    url: String,
    oauthParams: [String: String],
    parameters: [String: Sendable?]?
  ) throws -> String {
    guard let urlComponents = URLComponents(string: url) else {
      throw Networking.NetworkError.badUrl
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
}

// MARK: - Hawk Helper Methods
extension AuthorizeMethodGenerator {
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
}

// MARK: - AWS Helper Methods
extension AuthorizeMethodGenerator {
  private func createAWSCanonicalRequest(
    httpMethod: String,
    url: String,
    headers: [String: String]
  ) throws -> String {
    guard let urlComponents = URLComponents(string: url) else {
      throw Networking.NetworkError.badUrl
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
}