//
//  Data.swift
//  Networking
//
//  Created by Quân Đinh on 05.09.25.
//

import Foundation

// MARK: - Data Extensions
extension Data {
  var hexString: String {
    return self.map { String(format: "%02hhx", $0) }.joined()
  }
}

