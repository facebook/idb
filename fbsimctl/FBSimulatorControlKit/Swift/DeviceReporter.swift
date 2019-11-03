/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBDeviceControl
import Foundation

open class DeviceReporter: iOSReporter {
  public unowned let device: FBDevice
  public let reporter: EventReporter
  public let format: FBiOSTargetFormat

  init(device: FBDevice, format: FBiOSTargetFormat, reporter: EventReporter) {
    self.device = device
    self.format = format
    self.reporter = reporter
  }

  open var target: FBiOSTarget {
    return device
  }
}
