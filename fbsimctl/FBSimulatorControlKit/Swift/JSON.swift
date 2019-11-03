/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

/**
 Errors for the JSON Type
 */
public enum JSONError: Error {
  case notContainer(JSON)
  case nonEncodable(AnyObject)
  case serialization(NSError)
  case stringifying(Data)
  case parse(String)

  public var description: String {
    switch self {
    case let .notContainer(object):
      return "\(object) is not a container"
    case let .nonEncodable(object):
      return "\(object) is not JSON Encodable"
    case let .serialization(error):
      return "Serialization \(error.description)"
    case let .stringifying(data):
      return "Stringifying \(data.description)"
    case let .parse(string):
      return "Parsing \(string)"
    }
  }
}

/**
 The JSON Type.
 */
public indirect enum JSON {
  case dictionary([String: JSON])
  case array([JSON])
  case string(String)
  case number(NSNumber)
  case bool(Bool)
  case null

  static func encode(_ object: AnyObject) throws -> JSON {
    switch object {
    case let array as NSArray:
      var encoded: [JSON] = []
      for element in array {
        encoded.append(try encode(element as AnyObject))
      }
      return JSON.array(encoded)
    case let dictionary as NSDictionary:
      var encoded: [String: JSON] = [:]
      for (key, value) in dictionary {
        guard let key = key as? NSString else {
          throw JSONError.nonEncodable(object)
        }
        encoded[key as String] = try encode(value as AnyObject)
      }
      return JSON.dictionary(encoded)
    case let string as NSString:
      return JSON.string(string as String)
    case let number as NSNumber:
      return JSON.number(number)
    case is NSNull:
      return JSON.null
    default:
      throw JSONError.nonEncodable(object)
    }
  }

  static func fromData(_ data: Data) throws -> JSON {
    let object = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
    return try JSON.encode(object as AnyObject)
  }

  var data: Data {
    return try! JSONSerialization.data(withJSONObject: decode(), options: JSONSerialization.WritingOptions())
  }

  func decode() -> AnyObject {
    switch self {
    case let .dictionary(dictionary):
      let decoded = NSMutableDictionary()
      for (key, value) in dictionary {
        decoded[key] = value.decode()
      }
      return decoded.copy() as AnyObject
    case let .array(array):
      let decoded = NSMutableArray()
      for value in array {
        decoded.add(value.decode())
      }
      return decoded.copy() as AnyObject
    case let .string(string):
      return string as AnyObject
    case let .number(number):
      return number
    case let .bool(bool):
      return NSNumber(booleanLiteral: bool)
    case .null:
      return NSNull()
    }
  }

  public func decodeContainer() throws -> AnyObject {
    switch self {
    case .array:
      return decode()
    case .dictionary:
      return decode()
    default:
      throw JSONError.notContainer(self)
    }
  }

  func serializeToString(_ pretty: Bool) throws -> String {
    do {
      let writingOptions = pretty ? JSONSerialization.WritingOptions.prettyPrinted : JSONSerialization.WritingOptions()
      let jsonObject = try decodeContainer()
      let data = try JSONSerialization.data(withJSONObject: jsonObject, options: writingOptions)
      guard let string = String(data: data, encoding: String.Encoding.utf8) else {
        throw JSONError.stringifying(data)
      }
      return string
    } catch let error as JSONError {
      throw error
    } catch let error as NSError {
      throw JSONError.serialization(error)
    }
  }
}

/**
 Simple, Chainable Parsers for the JSON Type
 */
extension JSON {
  func getValue(_ key: String) throws -> JSON {
    guard let value = try getOptionalValue(key) else {
      throw JSONError.parse("Could not find \(key) in dictionary \(self)")
    }
    return value
  }

  func getOptionalValue(_ key: String) throws -> JSON? {
    switch self {
    case let .dictionary(dictionary):
      guard let value = dictionary[key] else {
        return nil
      }
      return value
    default:
      throw JSONError.parse("\(self) not a dictionary")
    }
  }

  func getOptionalArray() -> [JSON]? {
    switch self {
    case let .array(array):
      return array
    default:
      return nil
    }
  }

  func getArray() throws -> [JSON] {
    guard let array = getOptionalArray() else {
      throw JSONError.parse("\(self) not an array")
    }
    return array
  }

  func getOptionalDictionary() -> [String: JSON]? {
    switch self {
    case let .dictionary(dictionary):
      return dictionary
    default:
      return nil
    }
  }

  func getDictionary() throws -> [String: JSON] {
    guard let dictionary = getOptionalDictionary() else {
      throw JSONError.parse("\(self) not a dictionary")
    }
    return dictionary
  }

  func getString() throws -> String {
    switch self {
    case let .string(string):
      return string
    default:
      throw JSONError.parse("\(self) not a string")
    }
  }

  func getNumber() throws -> NSNumber {
    switch self {
    case let .number(number):
      return number
    default:
      throw JSONError.parse("\(self) is not a number")
    }
  }

  func getBool() throws -> Bool {
    switch self {
    case let .number(number):
      return number.boolValue
    case let .bool(bool):
      return bool
    default:
      throw JSONError.parse("\(self) is not a number/boolean")
    }
  }

  func getArrayOfStrings() throws -> [String] {
    return try getArray().map { try $0.getString() }
  }

  func getDictionaryOfStrings() throws -> [String: String] {
    var dictionary: [String: String] = [:]
    for (key, value) in try getDictionary() {
      dictionary[key] = try value.getString()
    }
    return dictionary
  }
}
