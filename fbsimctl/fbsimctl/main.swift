/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

let arguments = NSProcessInfo.processInfo().arguments.dropFirst(1)
let argumentSet = Set(arguments)
FBSimulatorControlGlobalConfiguration.setDebugLoggingEnabled(argumentSet.contains(Configuration.DEBUG_LOGGING_FLAG))

let environment = NSProcessInfo.processInfo().environment

Command
  .fromArguments(Array(NSProcessInfo.processInfo().arguments.dropFirst(1)), environment: environment)
  .runFromCLI()
