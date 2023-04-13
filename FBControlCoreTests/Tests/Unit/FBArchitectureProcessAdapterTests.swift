/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBArchitectureProcessAdapterTests: XCTestCase {

  var adapter: FBArchitectureProcessAdapter!
  var processConfiguration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>!
  let targetQueue = DispatchQueue(label: "test_queue", qos: .userInteractive)
  var tmpDir: FBTemporaryDirectory!

  override func setUp() {
    tmpDir = .init(logger: FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: true))
    adapter = .init()
    processConfiguration = .init(launchPath: TestFixtures.xctestBinary, arguments: [], environment: [:], io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(), mode: .posixSpawn)
  }

  override func tearDown() {
    tmpDir.cleanOnExit()
  }

  func testBinaryHasNotBeenModifiedForSameArchitecture() throws {
    let tmpdir = tmpDir.temporaryDirectory()
    let process = try adapter
      .adaptProcessConfiguration(processConfiguration, availableArchitectures: [.arm64], compatibleArchitecture: .arm64, queue: targetQueue, temporaryDirectory: tmpdir)
      .await(withTimeout: 10)

    XCTAssertEqual(process.launchPath, processConfiguration.launchPath)
  }

  func testX86_64ExtractedOnArchitectureMismatch() throws {
    let tmpdir = tmpDir.temporaryDirectory()
    let process = try adapter
      .adaptProcessConfiguration(processConfiguration, availableArchitectures: [.X86_64], compatibleArchitecture: .arm64, queue: targetQueue, temporaryDirectory: tmpdir)
      .await(withTimeout: 10)

    XCTAssertNotEqual(process.launchPath, processConfiguration.launchPath)
  }

  func testDyldFrameworkPathEnvVariableInProcessInfo() throws {
    let tmpdir = tmpDir.temporaryDirectory()
    let process = try adapter
      .adaptProcessConfiguration(processConfiguration, availableArchitectures: [.X86_64], compatibleArchitecture: .arm64, queue: targetQueue, temporaryDirectory: tmpdir)
      .await(withTimeout: 10)

    let frameworkPath = try XCTUnwrap(process.environment["DYLD_FRAMEWORK_PATH"])
    XCTAssertFalse(frameworkPath.isEmpty)
  }
}
