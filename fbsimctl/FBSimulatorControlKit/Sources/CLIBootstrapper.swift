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
    let (cli, writer, reporter, _) = CLI.fromArguments(arguments, environment: environment).bootstrap()
    return CLIRunner(cli: cli, writer: writer, reporter: reporter).runForStatus()
  }
}

struct CLIRunner : Runner {
  let cli: CLI
  let writer: Writer
  let reporter: EventReporter

  func run() -> CommandResult {
    switch self.cli {
    case .run(let command):
      return BaseCommandRunner(reporter: self.reporter, command: command).run()
    case .show(let help):
      return HelpRunner(reporter: self.reporter, help: help).run()
    case .print(let action):
      return PrintRunner(action: action, writer: self.writer).run()
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

struct PrintRunner : Runner {
  let action: Action
  let writer: Writer

  func run() -> CommandResult {
    switch self.action {
    case .core(let action):
      let output = action.printable()
      self.writer.write(output)
      return .success(nil)
    default:
      break
    }
    return .failure("Action \(self.action) not printable")
  }
}

extension CLI {
  struct CLIError : Error, CustomStringConvertible {
    let description: String
  }

  public static func fromArguments(_ arguments: [String], environment: [String : String]) -> CLI {
    do {
      let (_, cli) = try CLI.parser.parse(arguments)
      return cli.appendEnvironment(environment)
    } catch let error as (CustomStringConvertible & Error) {
      let help = Help(outputOptions: OutputOptions(), error: error, command: nil)
      return CLI.show(help)
    } catch {
      let error = CLIError(description: "An Unknown Error Occurred")
      let help = Help(outputOptions: OutputOptions(), error: error, command: nil)
      return CLI.show(help)
    }
  }

  public func bootstrap() -> (CLI, Writer, EventReporter, FBControlCoreLoggerProtocol)  {
    let writer = self.createWriter()
    let reporter = self.createReporter(writer)
    if case .run(let command) = self {
      let configuration = command.configuration
      let debugEnabled = configuration.outputOptions.contains(OutputOptions.DebugLogging)
      let bridge = ControlCoreLoggerBridge(reporter: reporter)
      let logger = LogReporter(bridge: bridge, debug: debugEnabled)
      FBControlCoreGlobalConfiguration.defaultLogger = logger
      return (self, writer, reporter, logger)
    }

    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    return (self, writer, reporter, logger)
  }

  private func createWriter() -> Writer {
    switch self {
    case .show:
      return FileHandleWriter.stdErrWriter
    case .print:
      return FileHandleWriter.stdOutWriter
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
