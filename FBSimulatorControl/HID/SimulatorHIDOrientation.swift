/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension SimulatorHIDDeviceOrientation {
  func vendorEvent() throws -> IndigoVendorDefinedEvent {
    let value: String
    switch self {
    case .portrait: value = "portrait"
    case .portraitUpsideDown: value = "pud"
    case .landscapeLeft: value = "landscape-left"
    case .landscapeRight: value = "landscape-right"
    }
    return try .virtualMachineControl(source: "orientation-picker-control", type: "enum", value: value)
  }
}

extension SimulatorHIDDeviceOrientation {
  // Purple takes interface-style landscape numbers, where BackBoard's physical device convention
  // swaps them.
  var physicalPurpleOrientation: Self {
    switch self {
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    case .portrait, .portraitUpsideDown: return self
    }
  }
}
