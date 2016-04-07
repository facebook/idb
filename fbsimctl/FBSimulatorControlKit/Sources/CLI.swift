// Copyright 2004-present Facebook. All Rights Reserved.

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

@objc public class CLI : NSObject {
  public static func bootstrap() -> Int32 {
    // The Parsing of Logging Arguments needs to be processes first, so that the Private Frameworks are not loaded
    let arguments = Array(NSProcessInfo.processInfo().arguments.dropFirst(1))
    do {
      let (_, configuration) = try FBSimulatorControlKit.Configuration.parser.parse(arguments)
      let debugEnabled = configuration.outputOptions.contains(OutputOptions.DebugLogging)

      let reporter = configuration.outputOptions.createReporter(configuration.outputOptions.createLogWriter())
      let bridge = ControlCoreLoggerBridge(reporter: reporter)
      let logger = LogReporter(bridge: bridge, debug: debugEnabled)
      FBControlCoreGlobalConfiguration.setDefaultLogger(logger)
    } catch {
      // Parse errors will be handled by the full parse
    }

    let environment = NSProcessInfo.processInfo().environment

    return Command
      .fromArguments(arguments, environment: environment)
      .runFromCLI()
  }
}
