/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorControlConfiguration)
public class FBSimulatorControlConfiguration: NSObject, NSCopying {

  // MARK: - Class Initialization

  private static let loadFrameworks: Void = {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
  }()

  // MARK: - Properties

  @objc public let deviceSetPath: String?
  @objc public let logger: FBControlCoreLogger
  @objc public let reporter: FBEventReporter?

  // MARK: - Initializers

  @objc(configurationWithDeviceSetPath:logger:reporter:)
  public class func configuration(
    withDeviceSetPath deviceSetPath: String?,
    logger: (any FBControlCoreLogger)?,
    reporter: (any FBEventReporter)?
  ) -> FBSimulatorControlConfiguration {
    return FBSimulatorControlConfiguration(
      deviceSetPath: deviceSetPath,
      logger: logger,
      reporter: reporter
    )
  }

  @objc
  public init(deviceSetPath: String?, logger: (any FBControlCoreLogger)?, reporter: (any FBEventReporter)?) {
    _ = FBSimulatorControlConfiguration.loadFrameworks
    self.deviceSetPath = deviceSetPath
    self.logger = logger ?? FBControlCoreGlobalConfiguration.defaultLogger
    self.reporter = reporter
    super.init()
  }

  // MARK: - NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: - NSObject

  public override var hash: Int {
    return deviceSetPath?.hash ?? 0
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorControlConfiguration else {
      return false
    }
    return deviceSetPath == other.deviceSetPath
  }

  public override var description: String {
    return "Pool Config | Set Path \(deviceSetPath ?? "(null)")"
  }

  // MARK: - Helpers

  @objc(defaultDeviceSetPath)
  public class var defaultDeviceSetPath: String {
    _ = loadFrameworks
    let deviceSetClass: AnyClass? = objc_lookUpClass("SimDeviceSet")
    assert(deviceSetClass != nil, "Expected SimDeviceSet to be loaded")
    let cls = deviceSetClass! as AnyObject
    let defaultSetPathSel = NSSelectorFromString("defaultSetPath")
    if let result = cls.perform(defaultSetPathSel)?.takeUnretainedValue() as? String {
      return result
    }
    let defaultSetSel = NSSelectorFromString("defaultSet")
    let setPathSel = NSSelectorFromString("setPath")
    let defaultSet = cls.perform(defaultSetSel)!.takeUnretainedValue()
    return (defaultSet as AnyObject).perform(setPathSel)!.takeUnretainedValue() as! String
  }
}
