/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

public enum JSONError : ErrorType {
  case NonEncodable(AnyObject)
  case Serialization(NSError)
  case Stringifying(NSData)

  public var description: String {
    get {
      switch self {
      case .NonEncodable(let object):
        return "\(object) is not JSON Encodable"
      case .Serialization(let error):
        return "Serialization \(error.description)"
      case .Stringifying(let data):
        return "Stringifying \(data.description)"
      }
    }
  }
}

public indirect enum JSON {
  case JDictionary([String : JSON])
  case JArray([JSON])
  case JString(String)
  case JNumber(NSNumber)
  case JNull

  static func encode(object: AnyObject) throws -> JSON {
    switch object {
    case let array as NSArray:
      var encoded: [JSON] = []
      for element in array {
        encoded.append(try encode(element))
      }
      return JSON.JArray(encoded)
    case let dictionary as NSDictionary:
      var encoded: [String : JSON] = [:]
      for (key, value) in dictionary {
        guard let key = key as? NSString else {
          throw JSONError.NonEncodable(object)
        }
        encoded[key as String] = try encode(value)
      }
      return JSON.JDictionary(encoded)
    case let string as NSString:
      return JSON.JString(string as String)
    case let number as NSNumber:
      return JSON.JNumber(number)
    case is NSNull:
      return JSON.JNull
    default:
      throw JSONError.NonEncodable(object)
    }
  }

  func decode() -> AnyObject {
    switch self {
    case .JDictionary(let dictionary):
      let decoded = NSMutableDictionary()
      for (key, value) in dictionary {
        decoded[key] = value.decode()
      }
      return decoded.copy()
    case .JArray(let array):
      let decoded = NSMutableArray()
      for value in array {
        decoded.addObject(value.decode())
      }
      return decoded.copy()
    case .JString(let string):
      return string
    case .JNumber(let number):
      return number
    case .JNull:
      return NSNull()
    }
  }

  func serializeToString(pretty: Bool) throws -> NSString {
    do {
      let writingOptions = pretty ? NSJSONWritingOptions.PrettyPrinted : NSJSONWritingOptions()
      let jsonObject = self.decode()
      let data = try NSJSONSerialization.dataWithJSONObject(jsonObject, options: writingOptions)
      guard let string = NSString(data: data, encoding: NSUTF8StringEncoding) else {
        throw JSONError.Stringifying(data)
      }
      return string
    } catch let error as NSError {
      throw JSONError.Serialization(error)
    }
  }
}

public protocol JSONDescribeable {
  var jsonDescription: JSON { get }
}
