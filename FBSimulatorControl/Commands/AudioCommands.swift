/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Reads and writes the simulated device's audio state.
public protocol AudioCommands: AnyObject {

  /// The simulated device's current audio settings.
  func audioSettings() async throws -> SimulatorAudioSettings

  /// Applies `update` to the simulated device, leaving any field it does not carry alone.
  ///
  /// The volume is the absolute counterpart to the `volumeUp` and `volumeDown` hardware buttons, which
  /// only step by a sixteenth.
  ///
  /// Do not mix the two: SpringBoard never reads back the level it publishes, so the next hardware
  /// button press steps from SpringBoard's stale level and overwrites what was set here. Control
  /// Center's slider is stale for the same reason, and the ringer behaves alike. An absolute set is
  /// reliable on its own.
  func updateAudioSettings(_ update: FBSimulatorAudioSettingsUpdate) async throws
}
