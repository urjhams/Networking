import Foundation

public final class Request: BaseRequest, @unchecked Sendable {

  public var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy

  public var baseURL: String = ""

  public var method: Networking.Method = .post

  public var parameters: [String: Sendable?]? = nil

  public var timeOut: TimeInterval = 60.0

  public var authorization: Networking.Authorization? = nil

  public required init() {}
}
