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

extension NSString : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}
extension NSString : FBDebugDescribeable {
  override public var debugDescription: String {
    get {
      return self.description
    }
  }

  public var shortDescription: String {
    get {
      return self.description
    }
  }
}

extension NSArray : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}
extension NSArray : FBDebugDescribeable {
  override public var debugDescription: String {
    get {
      return self.description
    }
  }

  public var shortDescription: String {
    get {
      return self.description
    }
  }
}

extension NSDictionary : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}

public struct JSON {
  public enum Error : ErrorType, CustomStringConvertible {
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

  let pretty: Bool

  func serializeToString(object: FBJSONSerializationDescribeable) throws -> String {
    do {
      let jsonObject = object.jsonSerializableRepresentation()
      try JSON.validateAsJSON(jsonObject)
      let data = try NSJSONSerialization.dataWithJSONObject(jsonObject, options: self.writingOptions)
      guard let string = NSString(data: data, encoding: NSUTF8StringEncoding) else {
        throw Error.Stringifying(data)
      }
      return string as String
    } catch let error as NSError {
      throw Error.Serialization(error)
    }
  }

  private static func validateAsJSON(object: AnyObject) throws {
    switch object {
    case let array as NSArray:
      for element in array {
        try self.validateAsJSON(element)
      }
    case let dictionary as NSDictionary:
      for (key, value) in dictionary {
        try self.validateAsJSON(key)
        try self.validateAsJSON(value)
      }
    case is NSString:
      return
    case is NSNumber:
      return
    case is NSNull:
      return
    default:
      throw JSON.Error.NonEncodable(object)
    }
  }

  private var writingOptions: NSJSONWritingOptions {
    get {
      return self.pretty ? NSJSONWritingOptions.PrettyPrinted : NSJSONWritingOptions()
    }
  }
}
