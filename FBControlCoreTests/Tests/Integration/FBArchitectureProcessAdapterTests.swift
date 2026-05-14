/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

// swiftlint:disable implicitly_unwrapped_optional
final class FBArchitectureProcessAdapterTests: XCTestCase {

  var adapter: FBArchitectureProcessAdapter!
  var processConfiguration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>!
  let targetQueue = DispatchQueue(label: "test_queue", qos: .userInteractive)
  var tmpDir: FBTemporaryDirectory!

  func getArchsInBinary(binary: String) throws -> String {
    try FBProcessBuilder<AnyObject, NSString, AnyObject>
      .withLaunchPath("/usr/bin/lipo", arguments: ["-archs", binary])
      .withStdOutInMemoryAsString()
      .withStdErrToDevNull()
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .onQueue(targetQueue, map: { p in p.stdOut ?? "" })
      .await(withTimeout: 2) as! String // swiftlint:disable:this force_cast
  }

  func adaptedProcess(requested: Set<FBArchitecture>, host: Set<FBArchitecture>) throws -> FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject> {
    let tmpdir = tmpDir.temporaryDirectory()
    return
      try adapter
      .adaptProcessConfiguration(processConfiguration, toAnyArchitectureIn: requested, hostArchitectures: host, queue: targetQueue, temporaryDirectory: tmpdir)
      .await(withTimeout: 10)
  }

  override func setUp() {
    tmpDir = .init(logger: FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: true, withDebugLogging: true))
    adapter = .init()
    processConfiguration = .init(launchPath: TestFixtures.xctestBinary, arguments: [], environment: [:], io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(), mode: .posixSpawn)
  }

  override func tearDown() {
    tmpDir.cleanOnExit()
  }

  func testBinaryIsThinnedDownTox86_64OnArm64Host() throws {
    let newConf = try adaptedProcess(requested: [.X86_64], host: [.X86_64, .arm64])
    XCTAssertNotEqual(newConf.launchPath, processConfiguration.launchPath)
    XCTAssertEqual(try getArchsInBinary(binary: newConf.launchPath), "x86_64")
  }

  func testBinaryIsThinnedDownTox86_64Onx86_64Host() throws {
    let newConf = try adaptedProcess(requested: [.X86_64, .arm64], host: [.X86_64])
    XCTAssertNotEqual(newConf.launchPath, processConfiguration.launchPath)
    XCTAssertEqual(try getArchsInBinary(binary: newConf.launchPath), "x86_64")
  }

  func testArm64ArchTakesPreference() throws {
    let newConf = try adaptedProcess(requested: [.X86_64, .arm64], host: [.X86_64, .arm64])
    XCTAssertNotEqual(newConf.launchPath, processConfiguration.launchPath)
    XCTAssertEqual(try getArchsInBinary(binary: newConf.launchPath), "arm64")
  }

  func testMismatchFails() throws {
    XCTAssertThrowsError(try adaptedProcess(requested: [.arm64], host: [.X86_64]))
  }

  func testDyldFrameworkPathEnvVariableInProcessInfo() throws {
    let process = try adaptedProcess(requested: [.X86_64], host: [.arm64, .X86_64])
    let frameworkPath = try XCTUnwrap(process.environment["DYLD_FRAMEWORK_PATH"])
    XCTAssertFalse(frameworkPath.isEmpty)
  }
}
