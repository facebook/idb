/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public struct DeviceInstrumentsCommands: InstrumentsCommands {
  private let device: FBDevice

  public static func commands(with device: FBDevice) -> DeviceInstrumentsCommands {
    DeviceInstrumentsCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  public func start(configuration: InstrumentsConfiguration, logger: any FBControlCoreLogger) async throws -> InstrumentsOperation {
    try await InstrumentsOperation.operation(target: device, configuration: configuration, logger: logger)
  }
}
