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

@objc public class CLIBootstrapper : NSObject {
  public static func bootstrap() -> Int32 {
    let arguments = Array(NSProcessInfo.processInfo().arguments.dropFirst(1))
    let environment = NSProcessInfo.processInfo().environment

    // The Parsing of Logging Arguments needs to be processes first, so that the Private Frameworks are not loaded
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
    let cli = CLI.fromArguments(arguments, environment: environment)
    let writer = FileHandleWriter.stdOutWriter
    return CLIRunner(cli: cli, writer: writer).runForStatus()
  }
}

struct CLIRunner : Runner {
  let cli: CLI
  let writer: Writer

  func run() -> CommandResult {
    let reporter = self.cli.createReporter(writer)

    switch self.cli {
    case .Run(let command):
      return BaseCommandRunner(reporter: reporter, command: command).run()
    case .Show(let help):
      return HelpRunner(reporter: reporter, help: help).run()
    }
  }

  func runForStatus() -> Int32 {
    switch self.run() {
      case .Failure: return 1
      case .Success: return 0
    }
  }
}
