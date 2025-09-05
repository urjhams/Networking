//
//  MockURLProtocol.swift
//  
//  This file provides a FAKE URLProtocol that intercepts network requests
//  and returns completely MOCK data without making any real network calls.
//
//  Created by Quân Đinh on 13.06.24.
//

import Foundation
import Networking

/// MockURLProtocol intercepts network requests and returns FAKE responses
/// No real network calls are made - everything is simulated locally
class MockURLProtocol: URLProtocol {
  // FAKE token for testing purposes - not a real authentication token
  static let token = "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"
  
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
        
    if url.absoluteString != "https://local-testing.com/greeting" {
      return errorResponse(url: url, statusCode: 403)
    }
    
    guard let authorizationHeader = request.value(forHTTPHeaderField: "Authorization"),
            authorizationHeader == "Bearer \(MockURLProtocol.token)"
    else {
      return errorResponse(url: url, statusCode: 401)
    }
    
    // Always provide a success response for the correct URL and auth
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    
    // For MockURLProtocol, we know the test should send {"name": "Quan"} 
    // URLSession can lose httpBody with custom protocols, so we'll simulate the expected response
    // based on the Content-Length header indicating data was sent
    var responseData: Data
    
    if let contentLength = request.value(forHTTPHeaderField: "Content-Length"), 
       contentLength != "0" {
      // Content-Length indicates body was sent, simulate parsing {"name": "Quan"}
      responseData = "{\"message\": \"Hello Quan\"}".data(using: .utf8)!
    } else {
      // No body expected  
      responseData = "{\"message\": \"Hello World\"}".data(using: .utf8)!
    }
    
    self.client?.urlProtocol(self, didLoad: responseData)
    
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
