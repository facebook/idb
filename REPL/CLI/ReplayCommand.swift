/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

import ArgumentParser
import Foundation

/// The `replay` subcommand: re-executes a previously recorded session from its report.
/// It reconstructs the context from the report, then re-runs each recorded run's code in
/// order — skipping runs that originally failed to compile — printing progress and each
/// run's output to stdout. `--realtime` paces the runs to match the original timing; a
/// `--report-path` writes a fresh, itself-replayable report of the replay.
struct ReplayCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "replay",
    abstract: "Replay a recorded idb-repl session from its report.",
    discussion: """
      The session context (simulator/test/app) and its target are read from the report; \
      for an app session the original launch mode is reproduced unless --new-session is \
      given. --report-failures here controls only whether compile failures encountered \
      during this replay are recorded in the new report; runs that failed to compile in \
      the source report are always skipped.
      """)

  @OptionGroup var connection: ConnectionOptions
  @OptionGroup var report: ReportOptions

  @Flag(name: .long, help: "Reproduce the original inter-run timing instead of running back-to-back.")
  var realtime = false

  @Flag(name: .long, help: "Force a clean app relaunch before replaying, overriding the launch mode recorded in the report.")
  var newSession = false

  @Argument(help: "Path to a session report (.md) produced by --report-path, to replay.")
  var reportFile: String

  func run() async throws {
    let expandedPath = (reportFile as NSString).expandingTildeInPath
    let text: String
    do {
      text = try String(contentsOfFile: expandedPath, encoding: .utf8)
    } catch {
      throw ValidationError("Could not read report at \(reportFile): \(error.localizedDescription)")
    }
    let parsed = try ReplReportParser.parse(text)

    if parsed.skippedFailedRuns > 0 {
      FileHandle.standardError.write(Data("idb-repl: skipping \(parsed.skippedFailedRuns) failed run(s) from the report\n".utf8))
    }
    guard !parsed.runs.isEmpty else {
      FileHandle.standardError.write(Data("idb-repl: no replayable runs in \(reportFile)\n".utf8))
      return
    }

    let session = try await ReplSession.start(
      context: parsed.context.asContext(forceNewSession: newSession),
      config: connection.sessionConfig(report: report))

    // Absolute offsets from replay start, so a slow replay never sleeps and the gaps
    // left by skipped compile failures are still reflected. Empty unless --realtime.
    let schedule = realtime ? ReplayTiming.offsets(forTimestamps: parsed.runs.map(\.timestamp)) : []
    let replayStart = Date()
    let total = parsed.runs.count

    for (index, run) in parsed.runs.enumerated() {
      if realtime {
        await ReplayTiming.waitUntil(replayStart.addingTimeInterval(schedule[index]))
      }
      let remaining = total - index - 1
      let firstLine = run.code.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
      print("▶ Run \(index + 1) of \(total) (\(remaining) remaining): \(firstLine)")
      do {
        let result = try await session.execute(code: run.code)
        print(result.output)
        if result.nextIndex < 0, index < total - 1 {
          FileHandle.standardError.write(Data("idb-repl: companion ended the session; stopping replay early\n".utf8))
          break
        }
      } catch let error as ReplExecutionError where !error.terminatesSession {
        // A run that now fails to compile (e.g. a different toolchain): report and continue.
        print("Error: \(error)")
      } catch {
        // A terminal error (session stopped / stream closed): stop the replay.
        print("Error: \(error)")
        break
      }
    }

    await session.finish()
  }
}

// MARK: -

extension ParsedContext {
  /// The context to start when replaying this parsed context. `forceNewSession` (from
  /// `replay --new-session`) forces a clean app relaunch; otherwise an app session
  /// reproduces the original launch mode — a clean relaunch if the app was freshly
  /// launched, or a reattach if the original resumed an already-running REPL.
  func asContext(forceNewSession: Bool) -> Context {
    switch self {
    case .simulator:
      return .simulator
    case let .test(bundlePath):
      return .test(bundlePath: bundlePath)
    case let .app(bundleID, freshLaunch):
      let reuseSession = forceNewSession ? false : !freshLaunch
      return .app(bundleID: bundleID, reuseSession: reuseSession)
    }
  }
}
