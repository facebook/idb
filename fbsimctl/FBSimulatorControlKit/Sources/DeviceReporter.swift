/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBDeviceControl

open class DeviceReporter : iOSReporter {
  unowned open let device: FBDevice
  open let reporter: EventReporter
  open let format: FBiOSTargetFormat

  init(device: FBDevice, format: FBiOSTargetFormat, reporter: EventReporter) {
    self.device = device
    self.format = format
    self.reporter = reporter
  }

  open var target: FBiOSTarget { get {
    return self.device
  }}
}
