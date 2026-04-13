/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A Protocol that defines a forwardable Commands Class.
@objc public protocol FBiOSTargetCommand: NSObjectProtocol {
  /// Instantiates the Commands instance.
  @objc(commandsWithTarget:)
  static func commands(with target: any FBiOSTarget) -> Self
}
