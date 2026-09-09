/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// An Option Set for Direct Launching.
///
/// The raw values are not contiguous; callers compare and persist them, so they must not change.
public struct FBSimulatorBootOptions: OptionSet, Hashable, Sendable {

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

public struct FBSimulatorBootConfiguration: Equatable, Hashable, Sendable, CustomStringConvertible {

  public let options: FBSimulatorBootOptions

  public let environment: [String: String]

  public static let `default` = FBSimulatorBootConfiguration(
    options: .verifyUsable,
    environment: [:]
  )

  public init(options: FBSimulatorBootOptions, environment: [String: String]) {
    self.options = options
    self.environment = environment
  }

  public var description: String {
    String(
      format: "Boot Environment %@ | Options %@",
      FBCollectionInformation.oneLineDescription(from: environment as [String: Any]),
      FBCollectionInformation.oneLineDescription(from: Self.stringsFromBootOptions(options) as [Any])
    )
  }

  private static let bootOptionStringDirectLaunch = "Direct Launch"

  private static func stringsFromBootOptions(_ options: FBSimulatorBootOptions) -> [String] {
    var strings: [String] = []
    if options.contains(.tieToProcessLifecycle) {
      strings.append(bootOptionStringDirectLaunch)
    }
    return strings
  }
}
