//
//  String.swift
//  Networking
//
//  Created by Quân Đinh on 05.09.25.
//

import Foundation

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
