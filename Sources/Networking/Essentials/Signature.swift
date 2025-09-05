//
//  File.swift
//  Networking
//
//  Created by Quân Đinh on 05.09.25.
//

import CryptoKit
import Foundation

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
