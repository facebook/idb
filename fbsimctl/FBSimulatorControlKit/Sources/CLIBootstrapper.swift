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
    let (cli, reporter, _) = CLI.fromArguments(arguments, environment: environment).bootstrap()
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
    // Start the runner
    let result = self.run()
    // Now we're done. Terminate any remaining asynchronous work
    for handle in result.handles {
      handle.terminate()
    }
    switch result.outcome {
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

extension CLI {
  public static func fromArguments(_ arguments: [String], environment: [String : String]) -> CLI {
    do {
      let (_, cli) = try CLI.parser.parse(arguments)
      return cli.appendEnvironment(environment)
    } catch let error {
      print("Failed to Parse Command \(error)")
      let help = Help(outputOptions: OutputOptions(), userInitiated: false, command: nil)
      return CLI.show(help)
    }
  }

  public func bootstrap() -> (CLI, EventReporter, FBControlCoreLoggerProtocol)  {
    let reporter = self.createReporter(self.createWriter())
    if case .run(let command) = self {
      let configuration = command.configuration
      let debugEnabled = configuration.outputOptions.contains(OutputOptions.DebugLogging)
      let bridge = ControlCoreLoggerBridge(reporter: reporter)
      let logger = LogReporter(bridge: bridge, debug: debugEnabled)
      FBControlCoreGlobalConfiguration.setDefaultLogger(logger)
      return (self, reporter, logger)
    }

    let logger = FBControlCoreGlobalConfiguration.defaultLogger()
    return (self, reporter, logger)
  }

  private func createWriter() -> Writer {
    switch self {
    case .show:
      return FileHandleWriter.stdErrWriter
    case .run(let command):
      return command.createWriter()
    }
  }
}

extension Command {
  func createWriter() -> Writer {
    for action in self.actions {
      if case .stream = action {
        return FileHandleWriter.stdErrWriter
      }
    }
    return FileHandleWriter.stdOutWriter
  }
}
