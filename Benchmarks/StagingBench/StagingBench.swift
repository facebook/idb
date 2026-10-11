/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import FBArtifactStaging
import FBControlCore
import Foundation

/// Measures how fast staging gets an archive from where it arrives onto disk -- fetch, decompress, extract -- with no
/// install after it, so the numbers are the archive pipeline's alone.
///
///     staging-bench run --output base.jsonl
///     staging-bench ab --base ./base-bench --head ./head-bench --output ab.jsonl
///     staging-bench compare ab.jsonl
@main
struct StagingBench: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "staging-bench",
    abstract: "Benchmark archive staging throughput.",
    subcommands: [Run.self, AB.self, Measure.self, Compare.self])
}

/// What to measure: every combination of these, each run several times.
struct Matrix: ParsableArguments {

  @Option(help: "Sources, comma separated: \(BenchSource.allCases.map(\.rawValue).joined(separator: ", ")).")
  var sources: String = BenchSource.allCases.map(\.rawValue).joined(separator: ",")

  @Option(help: "Formats, comma separated: \(BenchFormat.allCases.map(\.rawValue).joined(separator: ", ")).")
  var formats: String = BenchFormat.allCases.map(\.rawValue).joined(separator: ",")

  @Option(help: "Fixtures, comma separated, as <megabytes>x<files>, for example 400x10 or 400x10000.")
  var fixtures: String = "400x10,400x10000"

  @Option(help: "Whether fixture contents compress: compressible, incompressible, or both.")
  var contents: String = "compressible,incompressible"

  @Option(help: "Runs of each combination.")
  var runs: Int = 5

  @Flag(help: "A small matrix that runs in a few minutes, as a smoke test: 64 MB fixtures, two runs. Too noisy for a verdict.")
  var quick = false

  @Option(help: "Where fixtures are generated and kept between runs.")
  var workDirectory: String = NSTemporaryDirectory() + "staging-bench"

  func cases() throws -> [BenchCase] {
    let sources = try sources.split(separator: ",").map { try BenchSource.parse(String($0)) }
    let formats = try formats.split(separator: ",").map { try BenchFormat.parse(String($0)) }
    let contents = try contents.split(separator: ",").map { try FixtureContents.parse(String($0)) }
    let fixtures = quick ? [FixtureShape(megabytes: 64, files: 10), FixtureShape(megabytes: 64, files: 2000)] : try self.fixtures.split(separator: ",").map { try FixtureShape.parse(String($0)) }
    let cases = fixtures.flatMap { shape in
      contents.flatMap { contents in
        formats.flatMap { format in
          sources.map { BenchCase(source: $0, format: format, shape: shape, contents: contents) }
        }
      }
    }
    // A comparison of nothing finds no regression, which would pass a check that measured nothing.
    guard !cases.isEmpty else {
      throw ValidationError("The matrix is empty: give at least one source, format, fixture and kind of contents")
    }
    return cases
  }

  var effectiveRuns: Int { quick ? 2 : runs }
}

/// Generates the fixtures and measures each case `runs` times, each in a fresh process so that peak memory is the
/// run's own.
struct Run: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Measure every case with this binary.")

  @OptionGroup var matrix: Matrix

  @Option(help: "A label recorded with every result, such as a revision.")
  var label: String = "run"

  @Option(help: "Where to append one JSON line per measurement.")
  var output: String

  func run() async throws {
    let fixtures = Fixtures(root: URL(fileURLWithPath: matrix.workDirectory))
    let writer = try ResultWriter(path: output)
    for benchCase in try matrix.cases() {
      let archive = try fixtures.archive(benchCase.format, shape: benchCase.shape, contents: benchCase.contents)
      for _ in 0..<matrix.effectiveRuns {
        try writer.write(try Measurement.spawn(binary: CommandLine.arguments[0], benchCase: benchCase, archive: archive, label: label))
      }
    }
  }
}

/// Measures two binaries against each other on one host, alternating them run by run so that drift in the host's
/// load lands on both.
struct AB: AsyncParsableCommand {
  static let configuration = CommandConfiguration(commandName: "ab", abstract: "Measure two builds, interleaved, then compare them.")

  @OptionGroup var matrix: Matrix

  @Option(help: "The staging-bench binary built at the base revision.")
  var base: String

  @Option(help: "The staging-bench binary built at the revision under test.")
  var head: String

  @Option(help: "Where to append one JSON line per measurement.")
  var output: String

  func run() async throws {
    let fixtures = Fixtures(root: URL(fileURLWithPath: matrix.workDirectory))
    let writer = try ResultWriter(path: output)
    for benchCase in try matrix.cases() {
      let archive = try fixtures.archive(benchCase.format, shape: benchCase.shape, contents: benchCase.contents)
      for _ in 0..<matrix.effectiveRuns {
        try writer.write(try Measurement.spawn(binary: base, benchCase: benchCase, archive: archive, label: "base"))
        try writer.write(try Measurement.spawn(binary: head, benchCase: benchCase, archive: archive, label: "head"))
      }
    }
    let report = try Comparison(results: try ResultWriter.read(path: output), base: "base", head: "head", allowFewRuns: matrix.quick)
    print(report.table)
    if !report.regressions.isEmpty {
      throw ExitCode(1)
    }
  }
}

/// One measurement, in this process. `run` and `ab` spawn it rather than measuring in their own process, as peak
/// memory only ever rises.
struct Measure: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Measure one case once and print it as JSON.", shouldDisplay: false)

  @Option var source: String
  @Option var format: String
  @Option var megabytes: Int
  @Option var files: Int
  @Option var contents: String
  @Option var archive: String
  @Option var label: String

  func run() async throws {
    let benchCase = BenchCase(
      source: try BenchSource.parse(source), format: try BenchFormat.parse(format), shape: FixtureShape(megabytes: megabytes, files: files),
      contents: try FixtureContents.parse(contents))
    let measurement = try await Measurement.measure(benchCase, archive: URL(fileURLWithPath: archive), label: label)
    print(String(decoding: try JSONEncoder.sorted.encode(measurement), as: UTF8.self))
  }
}

/// Compares the runs of two labels in a results file.
struct Compare: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Compare two labels' results; exits 1 on a regression.")

  @Argument(help: "A results file written by run or ab.")
  var results: String

  @Option var base: String = "base"
  @Option var head: String = "head"

  @Flag(help: "Compare with fewer than five runs a side, for a smoke test; the verdicts are noise.")
  var allowFewRuns = false

  func run() throws {
    let report = try Comparison(results: try ResultWriter.read(path: results), base: base, head: head, allowFewRuns: allowFewRuns)
    print(report.table)
    if !report.regressions.isEmpty {
      throw ExitCode(1)
    }
  }
}

extension JSONEncoder {
  static var sorted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

/// Appends results as JSON lines.
struct ResultWriter {

  private let handle: FileHandle

  init(path: String) throws {
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: path, contents: nil)
    }
    handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try handle.seekToEnd()
  }

  func write(_ measurement: Measurement) throws {
    try handle.write(contentsOf: try JSONEncoder.sorted.encode(measurement) + Data("\n".utf8))
    FileHandle.standardError.write(Data("\(measurement.summary)\n".utf8))
  }

  /// Every measurement in `path`. A line that doesn't decode, such as the last line of a run that was killed, is
  /// skipped with a warning rather than discarding the rest.
  static func read(path: String) throws -> [Measurement] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").enumerated().compactMap { index, line in
      do {
        return try JSONDecoder().decode(Measurement.self, from: Data(line.utf8))
      } catch {
        FileHandle.standardError.write(Data("Skipping line \(index + 1) of \(path), which is not a measurement: \(error)\n".utf8))
        return nil
      }
    }
  }
}
