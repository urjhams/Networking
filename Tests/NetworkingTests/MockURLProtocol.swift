//
//  File.swift
//  
//
//  Created by Quân Đinh on 13.06.24.
//

import Foundation
import Networking

class MockURLProtocol: URLProtocol {
  static var token = "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"
  
  override class func canInit(with request: URLRequest) -> Bool {
    return request.url?.absoluteString.contains("https://local-testing.com") ?? false
  }
  
  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }
  
  override func startLoading() {
    guard let url = request.url else {
      return
    }
    
    print("😀", request.httpBody)
    
    if url.absoluteString != "https://local-testing.com/greeting" {
      return errorResponse(url: url, statusCode: 403)
    }
    
    
    guard let authorizationHeader = request.value(forHTTPHeaderField: "Authorization"),
            authorizationHeader == "Bearer \(MockURLProtocol.token)"
    else {
      return errorResponse(url: url, statusCode: 401)
    }
    
    var responseData: Data? = nil
    
    if let httpBody = request.httpBody,
        let parameters = try? JSONSerialization.jsonObject(with: httpBody, options: []) as? [String: Any],
        let name = parameters["name"] as? String {
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
      responseData = "{\"message\": \"Hello \(name)\"}".data(using: .utf8)
      self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    
    if let responseData {
      self.client?.urlProtocol(self, didLoad: responseData)
    }
    
    client?.urlProtocolDidFinishLoading(self)
  }
  
  private func errorResponse(url: URL, statusCode: Int) {
    let response = HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(
      self,
      didReceive: response,
      cacheStoragePolicy: .notAllowed
    )
    client?.urlProtocol(self, didLoad: Data())
    client?.urlProtocolDidFinishLoading(self)
  }
  
  override func stopLoading() {
    // No need to implement
  }
}
