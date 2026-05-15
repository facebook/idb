/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBProcessInfo)
public final class FBProcessInfo: NSObject, NSCopying {

  @objc public let processIdentifier: pid_t
  @objc public let launchPath: String
  @objc public let arguments: [String]
  @objc public let environment: [String: String]

  @objc public var processName: String {
    return (launchPath as NSString).lastPathComponent
  }

  @objc
  public init(processIdentifier: pid_t, launchPath: String, arguments: [String], environment: [String: String]) {
    self.processIdentifier = processIdentifier
    self.launchPath = launchPath
    self.arguments = arguments
    self.environment = environment
    super.init()
  }

  // MARK: NSObject

  public override var hash: Int {
    return Int(processIdentifier) ^ (launchPath as NSString).hash ^ (arguments as NSArray).hash
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBProcessInfo else { return false }
    return processIdentifier == other.processIdentifier
      && launchPath == other.launchPath
      && arguments == other.arguments
  }

  public override var description: String {
    return "Process \(processName) | PID \(processIdentifier)"
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }
}
