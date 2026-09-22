/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IOKit

extension SimulatorHIDDeviceOrientation {
  func vendorEvent() throws -> IndigoVendorDefinedEvent {
    let value: String
    switch self {
    case .portrait: value = "portrait"
    case .portraitUpsideDown: value = "pud"
    case .landscapeLeft: value = "landscape-left"
    case .landscapeRight: value = "landscape-right"
    }
    let payload: [String: String] = [
      "provider": "com.apple.Virtualization.VirtualMachines",
      "source": "orientation-picker-control",
      "type": "enum",
      "value": value,
    ]
    guard let serialized = IOCFSerialize(payload as CFDictionary, 1) else {
      throw SimulatorCoreDeviceError.unavailable("Could not serialize the simulator orientation input")
    }
    return IndigoVendorDefinedEvent(usagePage: 0xff61, usage: 0x5b, version: 0, data: serialized as Data)
  }
}
