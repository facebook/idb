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
  static func serializeToString(object: FBJSONSerializationDescribeable) throws -> String {
    do {
      let data = try NSJSONSerialization.dataWithJSONObject(object, options: NSJSONWritingOptions.PrettyPrinted)
      guard let string = NSString(data: data, encoding: NSUTF8StringEncoding) else {
        throw Error.Stringifying(data)
      }
      return string as String
    } catch let error as NSError {
      throw Error.Serialization(error)
    }
  }
}
