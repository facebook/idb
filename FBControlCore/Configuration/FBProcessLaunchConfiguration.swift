/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBProcessLaunchConfiguration)
public class FBProcessLaunchConfiguration: NSObject {

  @objc public let arguments: [String]
  @objc public let environment: [String: String]
  @objc public let io: FBProcessIO<AnyObject, AnyObject, AnyObject>

  @objc
  public init(arguments: [String], environment: [String: String], io: FBProcessIO<AnyObject, AnyObject, AnyObject>) {
    self.arguments = arguments
    self.environment = environment
    self.io = io
    super.init()
  }

  // MARK: NSObject

  public override var hash: Int {
    return (arguments as NSArray).hash ^ ((environment as NSDictionary).hash & io.hash)
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBProcessLaunchConfiguration,
      other.isKind(of: type(of: self))
    else {
      return false
    }
    return (arguments as NSArray).isEqual(to: other.arguments)
      && (environment as NSDictionary).isEqual(to: other.environment as NSDictionary)
      && io.isEqual(other.io)
  }
}
