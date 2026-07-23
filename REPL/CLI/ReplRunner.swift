/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

import ArgumentParser
import Foundation
import IDBGRPCSwift

/// Selects which context the REPL runs in, carrying the parameters each needs. Built
/// from CLI options by the subcommands and, for replay, reconstructed from a report.
enum Context {
  case simulator
  case test(bundlePath: String)
  case app(bundleID: String, reuseSession: Bool)

  /// The corresponding gRPC enum forwarded to the companion in the Start message.
  var proto: Idb_ReplRequest.Start.Context {
    switch self {
    case .simulator: return .simulator
    case .test: return .test
    case .app: return .app
    }
  }

  /// Short name for the context, recorded as a telemetry normal.
  var telemetryName: String {
    switch self {
    case .simulator: return "simulator"
    case .test: return "test"
    case .app: return "app"
    }
  }

  /// The machine-readable session metadata recorded in a report's header, from which
  /// `replay` reconstructs this context. `freshLaunch` is recorded for the app context
  /// (ignored otherwise).
  func sessionMeta(freshLaunch: Bool) -> SessionMeta {
    switch self {
    case .simulator:
      return SessionMeta(v: 1, context: "simulator", bundleID: nil, testBundlePath: nil, freshLaunch: nil)
    case let .test(bundlePath):
      return SessionMeta(v: 1, context: "test", bundleID: nil, testBundlePath: bundlePath, freshLaunch: nil)
    case let .app(bundleID, _):
      return SessionMeta(v: 1, context: "app", bundleID: bundleID, testBundlePath: nil, freshLaunch: freshLaunch)
    }
  }
}

/// A failure while compiling or executing REPL code. Its description is shown to
/// the user and recorded as the telemetry failure message.
enum ReplExecutionError: Error, CustomStringConvertible {
  case compileFailed(String)
  case sessionStopped(String)
  case unexpectedReady
  case streamClosed
  case notReady

  var description: String {
    switch self {
    case let .compileFailed(output):
      return output
    case let .sessionStopped(detail):
      return detail.isEmpty ? "idb_companion ended the REPL session" : detail
    case .unexpectedReady:
      return "idb_companion sent an unexpected 'ready' event instead of a result"
    case .streamClosed:
      return "idb_companion closed the REPL stream without returning a result"
    case .notReady:
      return "idb_companion did not report the REPL as ready"
    }
  }

  /// Whether the REPL session can no longer continue after this error.
  var terminatesSession: Bool {
    switch self {
    case .compileFailed, .unexpectedReady:
      return false
    case .sessionStopped, .streamClosed, .notReady:
      return true
    }
  }
}

/// A failure while retrieving a captured artifact from the companion.
enum ArtifactTransferError: Error, CustomStringConvertible {
  case extractionFailed(String)

  var description: String {
    switch self {
    case let .extractionFailed(path):
      return "Failed to extract the artifact archive at \(path)"
    }
  }
}

/// Shared REPL implementation backing the `test`, `simulator`, and `app` subcommands.
/// Its options are flattened into each subcommand via `@OptionGroup`. It establishes a
/// `ReplSession` and drives it either once (one-shot) or interactively.
struct ReplRunner: ParsableArguments {
  @OptionGroup var connection: ConnectionOptions
  @OptionGroup var report: ReportOptions

  @Argument(help: "An optional line of Swift to compile and run once, printing the result to stdout. If omitted, the interactive REPL starts.")
  var code: String?

  func run(context: Context) async throws {
    let session = try await ReplSession.start(
      context: context,
      config: connection.sessionConfig(report: report))

    // One-shot mode: when a line of code is supplied on the command line, compile
    // and run just that, print the result to stdout, and exit instead of starting
    // the interactive REPL.
    if let code {
      do {
        let result = try await session.execute(code: code)
        print(result.output)
      } catch {
        print("Error: \(error)")
      }
      await session.finish()
      return
    }

    printStatus("Connected to \(session.deviceType) \(session.osVersion) process.", "Type '/help' for available commands.")

    var lines: [String] = []
    let editor = LineEditor()

    inputLoop: while let input = editor.readLine() {
      let trimmed = input.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      if trimmed.hasPrefix("/") {
        print("")
        switch trimmed {
        case "/run":
          let swiftCode = lines.joined(separator: "\n")
          var stopSession = false
          do {
            let result = try await session.execute(code: swiftCode)
            printStatus(result.output)
          } catch {
            printStatus("Error:", "\(error)")
            stopSession = (error as? ReplExecutionError)?.terminatesSession ?? true
          }
          lines = []
          if stopSession {
            break inputLoop
          }
        case "/help":
          printHelp()
        case "/exit":
          break inputLoop
        default:
          printStatus("Unknown command: '\(trimmed)'. Type '/help' for available commands.")
        }
      } else {
        lines.append(input)
      }
    }

    await session.finish()
  }

  private func printHelp() {
    printStatus(
      "Available commands:",
      "  /help         Show this help message",
      "  /run          Compile and inject the entered Swift code",
      "  /exit         Kill subprocesses and exit",
      "",
      "Enter Swift code line by line, then type /run to execute."
    )
  }

  private func printStatus(_ lines: String...) {
    for line in lines {
      print(line)
    }
    print("")
  }
}
