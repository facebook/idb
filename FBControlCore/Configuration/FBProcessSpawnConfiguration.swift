/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBProcessSpawnMode)
public enum FBProcessSpawnMode: UInt {
  case `default` = 0
  case posixSpawn = 1
  case launchd = 2
}

@objc(FBProcessSpawnConfiguration)
public class FBProcessSpawnConfiguration: FBProcessLaunchConfiguration {

  @objc public let launchPath: String
  @objc public let mode: FBProcessSpawnMode

  @objc public var processName: String {
    return (launchPath as NSString).lastPathComponent
  }

  @objc
  public init(launchPath: String, arguments: [String], environment: [String: String], io: FBProcessIO<AnyObject, AnyObject, AnyObject>, mode: FBProcessSpawnMode) {
    self.launchPath = launchPath
    self.mode = mode
    super.init(arguments: arguments, environment: environment, io: io)
  }

  // MARK: NSObject

  public override var hash: Int {
    return super.hash | (launchPath as NSString).hash | Int(mode.rawValue)
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBProcessSpawnConfiguration,
      other.isKind(of: type(of: self))
    else {
      return false
    }
    return launchPath == other.launchPath
      && (arguments as NSArray).isEqual(to: other.arguments)
      && (environment as NSDictionary).isEqual(to: other.environment as NSDictionary)
      && mode == other.mode
  }

  public override var description: String {
    return "Process Launch \(launchPath) | Arguments \(FBCollectionInformation.oneLineDescription(from: arguments)) | Environment \(FBCollectionInformation.oneLineDescription(from: environment)) | Output \(io)"
  }
}
