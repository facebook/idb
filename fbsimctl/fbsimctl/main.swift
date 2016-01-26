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

// The Parsing of Logging Arguments needs to be processes first, so that the Privat Frameworks are not loaded
let arguments = Array(NSProcessInfo.processInfo().arguments.dropFirst(1))
do {
  let (_, configuration) = try Configuration.parser().parse(arguments)
  let debugEnabled = configuration.options.contains(Configuration.Options.DebugLogging)
  FBSimulatorControlGlobalConfiguration.setDebugLoggingEnabled(debugEnabled)
  FBSimulatorControlGlobalConfiguration.setStderrLoggingEnabled(true)
} catch {
  // Parse errors will be handled by the full parse
}

let environment = NSProcessInfo.processInfo().environment

let returnCode = Command
  .fromArguments(arguments, environment: environment)
  .runFromCLI()

exit(returnCode)
