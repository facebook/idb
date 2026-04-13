/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBLocationCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(overrideLocationWithLongitude:latitude:)
  func overrideLocation(withLongitude longitude: Double, latitude: Double) -> FBFuture<NSNull>
}
