/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

public struct JSONError : ErrorType {

}

public struct JSON {
  static func serializeToString(object: AnyObject) throws -> String {
    let data = try NSJSONSerialization.dataWithJSONObject(object, options: NSJSONWritingOptions.PrettyPrinted)
    guard let string = NSString(data: data, encoding: NSUTF8StringEncoding) else {
      throw JSONError()
    }
    return string as String
  }
}
