/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Reads the simulated device's audio state.
public protocol AudioCommands: AnyObject {

  /// The simulated device's current audio settings.
  func audioSettings() async throws -> FBSimulatorAudioSettings
}
