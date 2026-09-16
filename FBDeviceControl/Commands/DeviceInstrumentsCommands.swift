/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct DeviceInstrumentsCommands: InstrumentsCommands {
  private let device: Device

  public static func commands(with device: Device) -> DeviceInstrumentsCommands {
    DeviceInstrumentsCommands(device: device)
  }

  init(device: Device) {
    self.device = device
  }

  // MARK: - Async

  public func start(configuration: InstrumentsConfiguration, logger: any ControlCoreLogger) async throws -> InstrumentsOperation {
    try await InstrumentsOperation.operation(target: device, configuration: configuration, logger: logger)
  }
}
