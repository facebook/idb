/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBSimulatorBootConfiguration)
public class FBSimulatorBootConfiguration: NSObject, NSCopying {

  // MARK: Properties

  @objc public let options: FBSimulatorBootOptions

  @objc public let environment: [String: String]

  // MARK: Default Instance

  @objc(defaultConfiguration)
  public nonisolated(unsafe) static let `default` = FBSimulatorBootConfiguration(
    options: .verifyUsable,
    environment: [:]
  )

  // MARK: Initializers

  @objc
  public init(options: FBSimulatorBootOptions, environment: [String: String]) {
    self.options = options
    self.environment = environment
    super.init()
  }

  // MARK: - NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: - NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorBootConfiguration else {
      return false
    }
    return options == other.options && environment == other.environment
  }

  public override var hash: Int {
    return Int(bitPattern: options.rawValue) ^ (environment as NSDictionary).hash
  }

  public override var description: String {
    return String(
      format: "Boot Environment %@ | Options %@",
      FBCollectionInformation.oneLineDescription(from: environment as [String: Any]),
      FBCollectionInformation.oneLineDescription(from: Self.stringsFromBootOptions(options) as [Any])
    )
  }

  // MARK: - Private

  private static let bootOptionStringDirectLaunch = "Direct Launch"

  private static func stringsFromBootOptions(_ options: FBSimulatorBootOptions) -> [String] {
    var strings: [String] = []
    if options.contains(.tieToProcessLifecycle) {
      strings.append(bootOptionStringDirectLaunch)
    }
    return strings
  }
}
