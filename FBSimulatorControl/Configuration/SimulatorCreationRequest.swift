/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

public enum SimulatorSelector: Equatable, Sendable {
  case identifier(String)
  case name(String)

  func matches(identifier: String, name: String) -> Bool {
    switch self {
    case .identifier(let value): return value == identifier
    case .name(let value): return value == name
    }
  }
}

public struct SimulatorCreationRequest: Equatable, Sendable {
  public let device: SimulatorSelector
  public let runtime: SimulatorSelector?

  /// Omitting the runtime selects the newest available runtime compatible with the device.
  public init(device: SimulatorSelector, runtime: SimulatorSelector? = nil) {
    self.device = device
    self.runtime = runtime
  }
}
