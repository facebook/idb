/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// The DAP server runs a debugger adapter installed in the simulator's data directory on the host,
/// speaking the protocol over its standard streams. A script stands in for the adapter here.
final class SimulatorDapServerCommandTests: XCTestCase {

  private static let adapterPath = "dap/pkg/usr/bin/lldb-vscode"

  private var dataDirectory: URL!
  private var device: DataDirectoryDevice!

  override func setUpWithError() throws {
    dataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let adapter = dataDirectory.appendingPathComponent(Self.adapterPath)
    try FileManager.default.createDirectory(at: adapter.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Announces where it was told to log, then echoes the protocol stream back until it closes.
    try "#!/bin/sh\nprintf '%s\\n' \"$LLDBVSCODE_LOG\"\nexec cat\n".write(to: adapter, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adapter.path)
    device = DataDirectoryDevice(dataPath: dataDirectory.path)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dataDirectory)
    try? FileManager.default.removeItem(atPath: SimulatorTestSupport.testableSimulator(withDevice: device).coreSimulatorLogsDirectory)
  }

  func testServesTheAdapterOverItsStandardStreamsAndLogsToTheSimulatorLogs() async throws {
    let simulator = SimulatorTestSupport.testableSimulator(withDevice: device)
    let output = FBDataBuffer.accumulatingBuffer()
    let input = InputSource()

    let status = try await simulator.dapServer.withServer(Self.adapterPath, input: input, output: output) { process in
      input.write(Data("ping\n".utf8))
      input.finish()
      return try await process.terminationStatus
    }
    try await output.awaitFinishedConsuming()

    XCTAssertEqual(status, .exited(0))
    let lines = output.lines().filter { !$0.isEmpty }
    XCTAssertEqual(lines.count, 2, "\(lines)")
    let logPath = try XCTUnwrap(lines.first)
    XCTAssertEqual((logPath as NSString).deletingLastPathComponent, (simulator.coreSimulatorLogsDirectory as NSString).appendingPathComponent("dap"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: logPath), "The log file exists before the adapter starts")
    XCTAssertEqual(lines.last, "ping")
  }

  func testTerminatesTheAdapterWhenTheScopeExits() async throws {
    let simulator = SimulatorTestSupport.testableSimulator(withDevice: device)

    let process = try await simulator.dapServer.withServer(Self.adapterPath, input: InputSource(), output: FBDataBuffer.accumulatingBuffer()) { $0 }

    let status = try await process.terminationStatus
    XCTAssertEqual(status, .signalled(SIGTERM), "An adapter still reading its input is terminated rather than left running")
  }

  func testFailsWithoutADataDirectory() async throws {
    let simulator = SimulatorTestSupport.testableSimulator(withDevice: DataDirectoryDevice(dataPath: nil))
    defer { try? FileManager.default.removeItem(atPath: simulator.coreSimulatorLogsDirectory) }

    do {
      try await simulator.dapServer.withServer(Self.adapterPath, input: InputSource(), output: FBDataBuffer.accumulatingBuffer()) { _ in }
      XCTFail("Expected launching without a data directory to fail")
    } catch SimulatorDapServerError.noDataDirectory {
      // Expected.
    }
  }
}

// MARK: - Device double

private final class DataDirectoryDevice: NSObject {
  @objc(UDID) let udid = NSUUID()
  @objc let state = UInt64(TargetState.booted.rawValue)
  private let path: String?

  init(dataPath: String?) {
    self.path = dataPath
  }

  @objc func dataPath() -> String? {
    path
  }
}
