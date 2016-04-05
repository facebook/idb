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

/**
 Errors for the JSON Type
*/
public enum JSONError : ErrorType {
  case NonEncodable(AnyObject)
  case Serialization(NSError)
  case Stringifying(NSData)
  case Parse(String)

  public var description: String {
    get {
      switch self {
      case .NonEncodable(let object):
        return "\(object) is not JSON Encodable"
      case .Serialization(let error):
        return "Serialization \(error.description)"
      case .Stringifying(let data):
        return "Stringifying \(data.description)"
      case .Parse(let string):
        return "Parsing \(string)"
      }
    }
  }
}

/**
 The JSON Type.
 */
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

  static func fromData(data: NSData) throws -> JSON {
    let object = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions())
    return try JSON.encode(object)
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

/**
 Protocol for opting-in objects for being describeable in terms of the JSON Type.
 */
public protocol JSONDescribeable {
  var jsonDescription: JSON { get }
}
/**
 Automatic Coercions
 */
extension String : JSONDescribeable {
  public var jsonDescription: JSON { get {
    return JSON.JString(self)
  }}
}
extension Bool : JSONDescribeable {
  public var jsonDescription: JSON { get {
    return JSON.JNumber(NSNumber(bool: self))
  }}
}

/**
 Simple, Chainable Parsers for the JSON Type
*/
extension JSON {
  func getValue(key: String) throws -> JSON {
    guard let value = try getOptionalValue(key) else {
      throw JSONError.Parse("Could not find \(key) in dictionary \(self)")
    }
    return value
  }

  func getOptionalValue(key: String) throws -> JSON? {
    switch self {
    case .JDictionary(let dictionary):
      guard let value = dictionary[key] else {
        return nil
      }
      return value
    default:
      throw JSONError.Parse("\(self) not a dictionary")
    }
  }

  func getOptionalArray() -> [JSON]? {
    switch self {
    case .JArray(let array):
      return array
    default:
      return nil
    }
  }

  func getArray() throws -> [JSON] {
    guard let array = getOptionalArray() else {
      throw JSONError.Parse("\(self) not an array")
    }
    return array
  }

  func getOptionalDictionary() -> [String : JSON]? {
    switch self {
    case .JDictionary(let dictionary):
      return dictionary
    default:
      return nil
    }
  }

  func getDictionary() throws -> [String : JSON] {
    guard let dictionary = getOptionalDictionary() else {
       throw JSONError.Parse("\(self) not a dictionary")
    }
    return dictionary
  }

  func getString() throws -> String {
    switch self {
    case .JString(let string):
      return string
    default:
      throw JSONError.Parse("\(self) not a string")
    }
  }

  func getNumber() throws -> NSNumber {
    switch self {
    case .JNumber(let number):
      return number
    default:
      throw JSONError.Parse("\(self) is not a number")
    }
  }

  func getBool() throws -> Bool {
    switch self {
    case .JNumber(let number):
      return number.boolValue
    default:
      throw JSONError.Parse("\(self) is not a number/boolean")
    }
  }

  func getArrayOfStrings() throws -> [String] {
    return try self.getArray().map { try $0.getString() }
  }

  func getDictionaryOfStrings() throws -> [String : String] {
    var dictionary: [String : String] = [:]
    for (key, value) in try self.getDictionary() {
      dictionary[key] = try value.getString()
    }
    return dictionary
  }
}
