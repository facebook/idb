/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc
public class ProcessLaunchConfiguration: NSObject {

  @objc public let arguments: [String]
  @objc public let environment: [String: String]

  @objc
  public init(arguments: [String], environment: [String: String]) {
    self.arguments = arguments
    self.environment = environment
    super.init()
  }

  public override var hash: Int {
    (arguments as NSArray).hash ^ (environment as NSDictionary).hash
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? ProcessLaunchConfiguration,
      other.isKind(of: type(of: self))
    else {
      return false
    }
    return (arguments as NSArray).isEqual(to: other.arguments)
      && (environment as NSDictionary).isEqual(to: other.environment as NSDictionary)
  }
}
