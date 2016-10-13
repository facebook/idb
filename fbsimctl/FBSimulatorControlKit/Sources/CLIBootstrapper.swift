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

@objc open class CLIBootstrapper : NSObject {
  open static func bootstrap() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst(1))
    let environment = ProcessInfo.processInfo.environment

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
    let reporter = cli.createReporter(FileHandleWriter.stdOutWriter)
    return CLIRunner(cli: cli, reporter: reporter).runForStatus()
  }
}

struct CLIRunner : Runner {
  let cli: CLI
  let reporter: EventReporter

  func run() -> CommandResult {
    switch self.cli {
    case .run(let command):
      return BaseCommandRunner(reporter: self.reporter, command: command).run()
    case .show(let help):
      return HelpRunner(reporter: self.reporter, help: help).run()
    }
  }

  func runForStatus() -> Int32 {
    switch self.run() {
      case .failure(let message):
        self.reporter.reportError(message)
        return 1
      case .success(.some(let subject)):
        self.reporter.report(subject)
        fallthrough
      default:
        return 0
    }
  }
}
