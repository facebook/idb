/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

/// Reads and overrides what the simulated device draws in its status bar.
public struct SimulatorStatusBarCommands {

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> SimulatorStatusBarCommands {
    SimulatorStatusBarCommands(simulator: simulator)
  }

  internal init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Overrides

  public func currentStatusBarOverrides() async throws -> FBStatusBarOverride {
    var timeString: NSString?
    var dataNetworkType: NSNumber?
    var wiFiMode: NSNumber?
    var wiFiBars: NSNumber?
    var cellularMode: NSNumber?
    var operatorName: NSString?
    var cellularBars: NSNumber?
    var batteryState: NSNumber?
    var batteryLevel: NSNumber?
    var showNotCharging: NSNumber?
    try simulator.device.currentStatusBarOverrides(
      forTime: &timeString,
      dataNetworkType: &dataNetworkType,
      wiFiMode: &wiFiMode,
      wiFiBars: &wiFiBars,
      cellularMode: &cellularMode,
      operatorName: &operatorName,
      cellularBars: &cellularBars,
      batteryState: &batteryState,
      batteryLevel: &batteryLevel,
      showNotCharging: &showNotCharging)
    var override = FBStatusBarOverride()
    override.timeString = timeString as String?
    override.dataNetworkType = dataNetworkType
    override.wiFiMode = wiFiMode
    override.wiFiBars = wiFiBars
    override.cellularMode = cellularMode
    override.cellularBars = cellularBars
    override.operatorName = operatorName as String?
    override.batteryState = batteryState
    override.batteryLevel = batteryLevel
    override.showNotCharging = showNotCharging
    return override
  }

  public func overrideStatusBar(_ override: FBStatusBarOverride?) async throws {
    guard let override else {
      // clearStatusBarOverrides:(NSUInteger)flags sends @{@"OverridesToClear": @(flags)} via MIG.
      // Bit 31 (0x80000000) = clear all. Pass NSUIntegerMax to clear everything.
      try simulator.device.clearStatusBarOverrides(UInt.max)
      return
    }
    if let timeString = override.timeString {
      try simulator.device.overrideStatusBarTime(timeString)
    }
    if let dataNetworkType = override.dataNetworkType {
      try simulator.device.overrideStatusBarDataNetworkType(dataNetworkType.intValue)
    }
    if override.wiFiMode != nil || override.wiFiBars != nil {
      let mode = override.wiFiMode?.intValue ?? 3
      let bars = override.wiFiBars?.intValue ?? 3
      try simulator.device.overrideStatusBarWiFiMode(mode, bars: bars)
    }
    if override.cellularMode != nil || override.operatorName != nil || override.cellularBars != nil {
      let mode = override.cellularMode?.intValue ?? 3
      let name = override.operatorName ?? ""
      let bars = override.cellularBars?.intValue ?? 4
      try simulator.device.overrideStatusBarCellularMode(mode, operatorName: name, bars: bars)
    }
    if override.batteryState != nil || override.batteryLevel != nil || override.showNotCharging != nil {
      let state = override.batteryState?.intValue ?? 2
      let level = override.batteryLevel?.intValue ?? 100
      let notCharging = override.showNotCharging?.boolValue ?? false
      try simulator.device.overrideStatusBarBatteryState(state, batteryLevel: level, showNotCharging: notCharging)
    }
  }
}
