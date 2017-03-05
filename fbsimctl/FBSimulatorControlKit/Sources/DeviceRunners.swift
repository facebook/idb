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

struct DeviceActionRunner : Runner {
  let context: iOSRunnerContext<(Action, FBDevice)>

  func run() -> CommandResult {
    let (action, device) = self.context.value
    let reporter = DeviceReporter(device: device, format: self.context.format, reporter: self.context.reporter)
    let context = self.context.replace((action, device, reporter))

    switch (action) {
      default:
        return DeviceActionRunner.makeRunner(context).run()
    }
  }

  static func makeRunner(_ context: iOSRunnerContext<(Action, FBDevice, DeviceReporter)>) -> Runner {
    let (action, device, reporter) = context.value
    let covariantTuple: (Action, FBiOSTarget, iOSReporter) = (action, device, reporter)
    if let runner = iOSActionProvider(context: context.replace(covariantTuple)).makeRunner() {
      return runner
    }

    switch action {
    default:
      return CommandResultRunner.unimplementedActionRunner(action, target: device, format: context.format)
    }
  }
}
