/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import GRPCCore
import IDBGRPCSwift
import XCTest

final class IDBXCTestReporterCoverageTests: XCTestCase {

  private var workingDirectory: URL!
  private var coverageDirectory: URL!

  override func setUpWithError() throws {
    workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    coverageDirectory = workingDirectory.appendingPathComponent("coverage")
    try FileManager.default.createDirectory(at: coverageDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: workingDirectory)
  }

  func testExportedCoverage_IsTheGzippedLLVMExportOfTheProfiledBinary() async throws {
    let binary = try buildAndRunProfiledBinary()

    let data = try await exportCoverage(binariesPath: [binary.path])

    let export = try gunzip(data)
    XCTAssertTrue(export.contains("\"llvm.coverage.json.export\""), "Expected an llvm-cov JSON export, got: \(export.prefix(200))")
    XCTAssertTrue(export.contains("covered.c"), "The export should describe the profiled source")
  }

  func testExportedCoverage_WhenThereIsNothingToMerge_FailsWithTheMergeError() async throws {
    do {
      _ = try await exportCoverage(binariesPath: [])
      XCTFail("Merging an empty coverage directory should fail")
    } catch IDBXCTestReporterError.coverageExportFailed(let exitCode, let stderr) {
      XCTAssertNotEqual(exitCode, 0)
      XCTAssertFalse(stderr.isEmpty, "The merge tool's stderr should be carried in the error")
    }
  }

  func testExportedCoverage_WhenTheBinaryIsMissing_FailsWithTheExportError() async throws {
    _ = try buildAndRunProfiledBinary()
    let missing = workingDirectory.appendingPathComponent("missing").path

    do {
      _ = try await exportCoverage(binariesPath: [missing])
      XCTFail("Exporting against a missing binary should fail")
    } catch IDBXCTestReporterError.coverageExportFailed(let exitCode, let stderr) {
      XCTAssertNotEqual(exitCode, 0)
      XCTAssertTrue(stderr.contains("missing"), "The export tool's stderr should be carried in the error, got: \(stderr)")
    }
  }

  private func exportCoverage(binariesPath: [String]) async throws -> Data {
    let reporter = IDBXCTestReporter(
      responseStream: RPCWriter(wrapping: DiscardingWriter()),
      logger: IDBLogger(loggers: [FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: false)]))
    let profdataPath = coverageDirectory.appendingPathComponent("coverage.profdata")
    try await reporter.mergeRawCoverage(coverageDirectory: coverageDirectory, profdataPath: profdataPath)
    return try await reporter.exportCoverage(profdataPath: profdataPath, binariesPath: binariesPath)
  }

  private func buildAndRunProfiledBinary() throws -> URL {
    let source = workingDirectory.appendingPathComponent("covered.c")
    let binary = workingDirectory.appendingPathComponent("covered")
    try "int main(void) { return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
    try run("/usr/bin/xcrun", ["clang", "-fprofile-instr-generate", "-fcoverage-mapping", source.path, "-o", binary.path])
    try run(binary.path, [], environment: ["LLVM_PROFILE_FILE": coverageDirectory.appendingPathComponent("covered.profraw").path])
    return binary
  }

  private func gunzip(_ data: Data) throws -> String {
    let archive = workingDirectory.appendingPathComponent("export.json.gz")
    try data.write(to: archive)
    try run("/usr/bin/gunzip", [archive.path])
    return try String(contentsOf: archive.deletingPathExtension(), encoding: .utf8)
  }

  private func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, "\(executable) \(arguments) failed")
  }
}

private struct DiscardingWriter: RPCWriterProtocol {
  func write(_ element: Idb_XctestRunResponse) async throws {}
  func write(contentsOf elements: some Sequence<Idb_XctestRunResponse>) async throws {}
}
