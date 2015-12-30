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

protocol Runner {
  func run(writer: Writer) -> ActionResult
}

extension Configuration {
  func build() -> FBSimulatorControl {
    let logger = FBSimulatorLogger.aslLogger().writeToStderrr(true, withDebugLogging: self.debugLogging)
    return try! FBSimulatorControl.withConfiguration(self.controlConfiguration, logger: logger)
  }
}

public extension Command {
  func runFromCLI() -> Void {
    let writer = StdIOWriter()
    switch (BaseRunner(command: self).run(StdIOWriter())) {
    case .Failure(let string):
      writer.writeOut(string)
    default:
      break
    }
  }
}

private struct SequenceRunner : Runner {
  let runners: [Runner]

  func run(writer: Writer) -> ActionResult {
    var output = ActionResult.Success
    for runner in runners {
      output = output.append(runner.run(writer))
      switch output {
        case .Failure: return output
        default: continue
      }
    }
    return output
  }
}

private struct BaseRunner : Runner {
  let command: Command

  func run(writer: Writer) -> ActionResult {
    switch (self.command) {
    case .Help:
      writer.write(Command.getHelp())
      return .Success
    case .Interact(let configuration, let port):
      return InteractionRunner(control: configuration.build(), portNumber: port).run(writer)
    case .Perform(let configuration, let actions):
      return SequenceRunner(runners: actions.map { ActionRunner(action: $0, control: configuration.build()) } ).run(writer)
    }
  }
}


private struct ActionRunner : Runner {
  let action: Action
  let control: FBSimulatorControl

  func run(writer: Writer) -> ActionResult {
    switch (self.action) {
    case .List(let query, let format):
      let simulators = Query.perform(control.simulatorPool, query: query)
      writer.write(Format.formatAll(format)(simulators: simulators))
      return .Success
    case .Boot(let query):
      return self.runWithQuery(query, writer) { simulator in
        writer.write("Booting \(simulator.udid)")
        try simulator.interact().bootSimulator().performInteraction()
        writer.write("Booted \(simulator.udid)")
      }
    case .Shutdown(let query):
      return self.runWithQuery(query, writer) { simulator in
        writer.write("Shutting Down \(simulator.udid)")
        try simulator.interact().shutdownSimulator().performInteraction()
        writer.write("Shutdown \(simulator.udid)")
      }
    case .Diagnose(let query):
      return self.runWithQuery(query, writer) { simulator in
        if let sysLog = simulator.logs.systemLog() {
          writer.write("\(sysLog.shortName) \(sysLog.asPath)")
        }
      }
    default:
      return .Failure("unimplemented")
    }
  }

  private func runWithQuery(query: Query, _ writer: Writer, _ transform: FBSimulator throws -> Void) -> ActionResult {
    return QueryRunner(query: query, control: self.control, transform: transform).run(writer)
  }
}

private struct QueryRunner : Runner {
  let query: Query
  let control: FBSimulatorControl
  let transform: FBSimulator throws -> Void

  func run(writer: Writer) -> ActionResult {
    let simulators = Query.perform(self.control.simulatorPool, query: query)
    return SequenceRunner(runners: simulators.map { SimulatorRunner(simulator: $0, transform: self.transform) } ).run(writer)
  }

  struct SimulatorRunner : Runner {
    let simulator: FBSimulator
    let transform: FBSimulator throws -> Void

    func run(writer: Writer) -> ActionResult {
      do {
        try self.transform(self.simulator)
        return .Success
      } catch let error as NSError {
        return .Failure(error.description)
      }
    }
  }
}

private class InteractionRunner : Runner, RelayTransformer {
  let control: FBSimulatorControl
  let portNumber: Int?

  init(control: FBSimulatorControl, portNumber: Int?) {
    self.control = control
    self.portNumber = portNumber
  }

  func run(writer: Writer) -> ActionResult {
    if let portNumber = self.portNumber {
      writer.write("Starting Socket server on \(portNumber)")
      SocketRelay(portNumber: portNumber, transformer: self).start()
      writer.write("Ending Socket Server")
    } else {
      writer.write("Starting local interactive mode, listening on stdin")
      StdIORelay(transformer: self).start()
      writer.write("Ending local interactive mode")
    }
    return .Success
  }

  func transform(input: String, writer: Writer) -> ActionResult {
    let arguments = input.componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
    do {
      let (_, action) = try Action.parser().parse(arguments)
      let runner = ActionRunner(action: action, control: self.control)
      return runner.run(writer)
    } catch let error as NSError {
      return .Failure(error.description)
    } catch _ as ParseError {
      return .Failure("Failed to parse '\(input)'")
    }
  }
}

private extension Query {
  static func perform(pool: FBSimulatorPool, query: Query) -> [FBSimulator] {
    let array: NSArray = pool.allSimulators
    return array.filteredArrayUsingPredicate(query.get(pool)) as! [FBSimulator]
  }

  func get(pool: FBSimulatorPool) -> NSPredicate {
    switch (self) {
    case .UDID(let udids):
      return FBSimulatorPredicates.udids(Array(udids))
    case .State(let states):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: states.map(FBSimulatorPredicates.state) as! [NSPredicate]
      )
    case .Configured(let configurations):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: configurations.map(FBSimulatorPredicates.configuration) as! [NSPredicate]
      )
    case .And(let subqueries):
      return NSCompoundPredicate(
        andPredicateWithSubpredicates: subqueries.map { $0.get(pool) }
      )
    }
  }
}

private extension Format {
  static func format(format: Format)(simulator: FBSimulator) -> String {
    switch (format) {
    case Format.UDID:
      return simulator.udid
    case Format.Name:
      return simulator.name
    case Format.DeviceName:
      return simulator.configuration.deviceName
    case Format.OSVersion:
      return simulator.configuration.osVersionString
    case Format.Compound(let subformats):
      let tokens: NSArray = subformats.map { Format.format($0)(simulator: simulator) }
      return tokens.componentsJoinedByString(" ")
    }
  }

  static func formatAll(format: Format)(simulators: [FBSimulator]) -> String {
    return simulators
      .map(Format.format(format))
      .joinWithSeparator("\n")
  }
}
