/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// An Option Set for Direct Launching.
///
/// The raw values are not contiguous, and are kept as they were when this was an `NS_OPTIONS`:
/// they are compared and persisted by callers.
public struct FBSimulatorBootOptions: OptionSet, Sendable {

  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  /// Ties the Simulator's lifecycle to that of the launching process, so that the Simulator is
  /// shut down automatically when the process that booted it dies.
  public static let tieToProcessLifecycle = FBSimulatorBootOptions(rawValue: 1 << 1)

  /// Requires that the Simulator is 'Usable' before the boot API completes. A Simulator can report
  /// itself 'Booted' very quickly while not yet being usable.
  public static let verifyUsable = FBSimulatorBootOptions(rawValue: 1 << 3)
}

@objc(FBSimulatorBootConfiguration)
public class FBSimulatorBootConfiguration: NSObject, NSCopying {

  // MARK: Properties

  public let options: FBSimulatorBootOptions

  @objc public let environment: [String: String]

  // MARK: Default Instance

  @objc(defaultConfiguration)
  public nonisolated(unsafe) static let `default` = FBSimulatorBootConfiguration(
    options: .verifyUsable,
    environment: [:]
  )

  // MARK: Initializers

  public init(options: FBSimulatorBootOptions, environment: [String: String]) {
    self.options = options
    self.environment = environment
    super.init()
  }

  // MARK: - NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  // MARK: - NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorBootConfiguration else {
      return false
    }
    return options == other.options && environment == other.environment
  }

  public override var hash: Int {
    Int(bitPattern: options.rawValue) ^ (environment as NSDictionary).hash
  }

  public override var description: String {
    String(
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
