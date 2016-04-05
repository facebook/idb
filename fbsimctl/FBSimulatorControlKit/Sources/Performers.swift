/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A Protocol for performing an Command producing an CommandResult.
 */
protocol CommandPerformer {
  func perform(command: Command, reporter: EventReporter) -> CommandResult
}

/**
 Forwards to a CommandPerformer based on Constructor Arguments
 */
struct ActionPerformer {
  let commandPerformer: CommandPerformer
  let configuration: Configuration
  let query: Query?
  let format: Format?

  func perform(action: Action, reporter: EventReporter) -> CommandResult {
    let command = Command.Perform(self.configuration, [action], self.query, self.format)
    return self.commandPerformer.perform(command, reporter: reporter)
  }
}

extension CommandPerformer {
  func perform(input: String, reporter: EventReporter) -> CommandResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, command) = try Command.parser.parse(arguments)
      return self.perform(command, reporter: reporter)
    } catch let error as ParseError {
      return .Failure("Error: \(error.description)")
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

/**
 Enum for defining the result of a translation.
 */
public enum CommandResult {
  case Success
  case Failure(String)

  func append(second: CommandResult) -> CommandResult {
    switch (self, second) {
    case (.Success, .Success):
      return .Success
    case (.Success, .Failure(let secondString)):
      return .Failure(secondString)
    case (.Failure(let firstString), .Success):
      return .Failure(firstString)
    case (.Failure(let firstString), .Failure(let secondString)):
      return .Failure("\(firstString)\n\(secondString)")
    }
  }
}

extension CommandResult : CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    get {
      switch self {
      case .Success: return "Success"
      case .Failure(let string): return "Failure '\(string)'"
      }
    }
  }

  public var debugDescription: String {
    get {
      return self.description
    }
  }
}

protocol SimulatorControlActionPerformer {
  func perform() -> CommandResult
}

struct SimulatorAction : SimulatorControlActionPerformer {
  let reporter: SimulatorReporter
  let name: EventName?
  let subject: EventReporterSubject
  let action: Void throws -> Void

  init(_ reporter: SimulatorReporter, _ name: EventName?, _ subject: EventReporterSubject, _ action: Void throws -> Void) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.action = action
  }

  func perform() -> CommandResult {
    do {
      if let name = self.name {
        self.reporter.report(name, EventType.Started, self.subject)
      }
      try self.action()
      if let name = self.name {
        self.reporter.report(name, EventType.Ended, self.subject)
      }
    } catch let error as NSError {
      return .Failure(error.description)
    } catch let error as JSONError {
      return .Failure(error.description)
    }
    return .Success
  }
}

struct SimulatorInteraction : SimulatorControlActionPerformer {
  let reporter: SimulatorReporter
  let name: EventName
  let subject: EventReporterSubject
  let interaction: FBSimulatorInteraction throws -> Void

  init(_ reporter: SimulatorReporter, _ name: EventName, _ subject: EventReporterSubject, _ interaction: FBSimulatorInteraction throws -> Void) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.interaction = interaction
  }

  func perform() -> CommandResult {
    let simulator = self.reporter.simulator
    let interaction = self.interaction
    let action = SimulatorAction(self.reporter, self.name, self.subject) {
      let interact = simulator.interact
      try interaction(interact)
      try interact.perform()
    }
    return action.perform()
  }
}

struct DiagnosticsInteraction : SimulatorControlActionPerformer {
  let reporter: SimulatorReporter
  let subject: ControlCoreValue
  let query: FBSimulatorDiagnosticQuery
  let format: DiagnosticFormat

  init(_ reporter: SimulatorReporter, _ subject: ControlCoreValue, _ query: FBSimulatorDiagnosticQuery, _ format: DiagnosticFormat) {
    self.reporter = reporter
    self.subject = subject
    self.query = query
    self.format = format
  }

  func perform() -> CommandResult {
    let diagnostics = self.fetchDiagnostics()

    reporter.reportValue(EventName.Diagnose, EventType.Started, query)
    for diagnostic in diagnostics {
      reporter.reportValue(EventName.Diagnostic, EventType.Discrete, diagnostic)
    }
    reporter.reportValue(EventName.Diagnose, EventType.Ended, query)
    return .Success
  }

  func fetchDiagnostics() -> [FBDiagnostic] {
    let diagnostics = self.reporter.simulator.diagnostics
    let format = self.format

    return query.perform(diagnostics).map { diagnostic in
      switch format {
      case .CurrentFormat:
        return diagnostic
      case .Content:
        return FBDiagnosticBuilder(diagnostic: diagnostic).readIntoMemory().build()
      case .Path:
        return FBDiagnosticBuilder(diagnostic: diagnostic).writeOutToFile().build()
      }
    }
  }
}

struct SearchInteraction : SimulatorControlActionPerformer {
  let reporter: SimulatorReporter
  let search: FBBatchLogSearch

  init(_ reporter: SimulatorReporter, _ search: FBBatchLogSearch) {
    self.reporter = reporter
    self.search = search
  }

  func perform() -> CommandResult {
    let simulator = self.reporter.simulator
    let diagnostics = simulator.diagnostics.allDiagnostics()
    let results = search.search(diagnostics)
    self.reporter.report(EventName.Search, EventType.Discrete, ControlCoreSubject(results))
    return .Success
  }
}

struct UploadInteraction : SimulatorControlActionPerformer {
  let reporter: SimulatorReporter
  let diagnostics: [FBDiagnostic]

  init(_ reporter: SimulatorReporter, _ diagnostics: [FBDiagnostic]) {
    self.reporter = reporter
    self.diagnostics = diagnostics
  }

  func perform() -> CommandResult {
    let diagnosticLocations: [(FBDiagnostic, String)] = diagnostics.map { diagnostic in
      return (diagnostic, diagnostic.asPath)
    }
    let mediaPredicate = NSPredicate.predicateForMediaPaths()
    let media = diagnosticLocations.filter { mediaPredicate.evaluateWithObject($0.1) }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let interaction = SimulatorInteraction(self.reporter, EventName.Upload, ArraySubject(paths)) { interaction in
        interaction.uploadMedia(paths)
      }
      let result = interaction.perform()
      switch result {
      case .Failure: return result
      default: break
      }
    }

    guard let basePath: NSString = self.reporter.simulator.auxillaryDirectory else {
        return CommandResult.Failure("Could not determine aux directory for simulator \(self.reporter.simulator) to path")
    }
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter{ arbitraryPredicate.evaluateWithObject($0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOutToDirectory(basePath as String) else {
        return CommandResult.Failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      self.reporter.report(EventName.Upload, EventType.Discrete, ControlCoreSubject(destinationDiagnostic))
    }

    return CommandResult.Success
  }
}
