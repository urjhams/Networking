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

/// A lightweight URLProtocol that lets tests supply a per-request handler.
/// This avoids hardcoded URLs/tokens and keeps stubbing local to each test.
final class MockURLProtocol: URLProtocol {

  override class func canInit(with request: URLRequest) -> Bool {
    // Intercept all requests for the URLSession that installs this protocol.
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    do {
      let (response, data) = try MockServer.resolve(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() { /* no-op */ }
}
