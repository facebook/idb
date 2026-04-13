/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBApplicationLaunchMode)
public enum FBApplicationLaunchMode: UInt {
  case failIfRunning = 0
  case foregroundIfRunning = 1
  case relaunchIfRunning = 2
}

@objc(FBApplicationLaunchConfiguration)
public class FBApplicationLaunchConfiguration: FBProcessLaunchConfiguration {

  @objc public let bundleID: String
  @objc public let bundleName: String?
  @objc public let waitForDebugger: Bool
  @objc public let launchMode: FBApplicationLaunchMode

  @objc
  public init(bundleID: String, bundleName: String?, arguments: [String], environment: [String: String], waitForDebugger: Bool, io: FBProcessIO<AnyObject, AnyObject, AnyObject>, launchMode: FBApplicationLaunchMode) {
    self.bundleID = bundleID
    self.bundleName = bundleName
    self.waitForDebugger = waitForDebugger
    self.launchMode = launchMode
    super.init(arguments: arguments, environment: environment, io: io)
  }

  // MARK: NSObject

  public override var hash: Int {
    return super.hash ^ (bundleID as NSString).hash ^ ((bundleName as NSString?)?.hash ?? 0) &+ (waitForDebugger ? 1231 : 1237)
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard super.isEqual(object),
      let other = object as? FBApplicationLaunchConfiguration
    else {
      return false
    }
    return bundleID == other.bundleID
      && bundleName == other.bundleName
      && waitForDebugger == other.waitForDebugger
      && launchMode == other.launchMode
  }

  public override var description: String {
    return "App Launch \(bundleID) (\(bundleName ?? "(null)"))"
  }
}
