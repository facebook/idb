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
    let input = FBProcessInput<DataConsumer>.fromConsumer()

    let process = try await simulator.dapServer.launch(Self.adapterPath, stdIn: input.retyped(FBProcessInput<AnyObject>.self), stdOut: output)
    input.contents.consumeData(Data("ping\n".utf8))
    input.contents.consumeEndOfFile()
    _ = try await bridgeFBFuture(process.statLoc)
    _ = try await bridgeFBFuture(output.finishedConsuming)

    let lines = output.lines().filter { !$0.isEmpty }
    XCTAssertEqual(lines.count, 2, "\(lines)")
    let logPath = try XCTUnwrap(lines.first)
    XCTAssertEqual((logPath as NSString).deletingLastPathComponent, (simulator.coreSimulatorLogsDirectory as NSString).appendingPathComponent("dap"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: logPath), "The log file exists before the adapter starts")
    XCTAssertEqual(lines.last, "ping")
  }

  func testFailsWithoutADataDirectory() async throws {
    let simulator = SimulatorTestSupport.testableSimulator(withDevice: DataDirectoryDevice(dataPath: nil))
    defer { try? FileManager.default.removeItem(atPath: simulator.coreSimulatorLogsDirectory) }

    do {
      _ = try await simulator.dapServer.launch(Self.adapterPath, stdIn: FBProcessInput<DataConsumer>.fromConsumer().retyped(FBProcessInput<AnyObject>.self), stdOut: FBDataBuffer.accumulatingBuffer())
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
