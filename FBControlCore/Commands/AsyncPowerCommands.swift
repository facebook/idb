/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBPowerCommands`.
public protocol AsyncPowerCommands: AnyObject {

  func shutdown() async throws

  func reboot() async throws
}
