/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl

// The commands that run inside the simulator through the SimulatorFrameworkBridge guest, added onto
// `Simulator` from outside FBSimulatorControl so that consumers that use none of them do not ship
// the guest.
extension Simulator {
  public var orientation: SimulatorOrientationCommands {
    SimulatorOrientationCommands(simulator: self)
  }

  public var privacy: SimulatorPrivacyCommands {
    SimulatorPrivacyCommands(simulator: self)
  }

  public var preferences: SimulatorPreferencesCommands {
    SimulatorPreferencesCommands(simulator: self)
  }

  public var network: SimulatorNetworkCommands {
    SimulatorNetworkCommands(simulator: self)
  }

  public var health: SimulatorHealthCommands {
    SimulatorHealthCommands(simulator: self)
  }

  public var contacts: SimulatorContactsCommands {
    SimulatorContactsCommands(simulator: self)
  }

  public var photos: SimulatorPhotosCommands {
    SimulatorPhotosCommands(simulator: self)
  }

  public var notification: SimulatorNotificationCommands {
    SimulatorNotificationCommands(simulator: self)
  }

  public var lockScreen: SimulatorLockScreenCommands {
    SimulatorLockScreenCommands(simulator: self)
  }
}
