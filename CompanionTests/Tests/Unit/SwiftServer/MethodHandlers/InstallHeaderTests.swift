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

final class InstallHeaderTests: XCTestCase {

  private static let destination = request { $0.destination = .dsym }
  private static let nameHint = request { $0.nameHint = "A" }
  private static let makeDebuggable = request { $0.makeDebuggable = true }
  private static let overrideModificationTime = request { $0.overrideModificationTime = true }
  private static let skipSigningBundles = request { $0.skipSigningBundles = true }
  private static let link = request { $0.linkDsymToBundle = .with { $0.bundleID = "com.example.app" } }
  private static let zstd = request { $0.payload = .with { $0.compression = .zstd } }
  private static let data = request { $0.payload = .with { $0.data = Data([1, 2, 3]) } }

  private static func request(_ configure: (inout Idb_InstallRequest) -> Void) -> Idb_InstallRequest {
    Idb_InstallRequest.with(configure)
  }

  private func read(_ frames: [Idb_InstallRequest]) async throws -> InstallHeader {
    var remaining = frames[...]
    return try await InstallHeader.read {
      guard let frame = remaining.popFirst() else {
        throw RPCError(code: .invalidArgument, message: "Stream ended")
      }
      return frame
    }
  }

  private func assertRejected(_ frames: [Idb_InstallRequest], _ code: RPCError.Code, _ message: String, file: StaticString = #filePath, line: UInt = #line) async {
    do {
      _ = try await read(frames)
      XCTFail("Expected \(code)", file: file, line: line)
    } catch let error as RPCError {
      XCTAssertEqual(error.code, code, file: file, line: line)
      XCTAssertEqual(error.message, message, file: file, line: line)
    } catch {
      XCTFail("Expected an RPCError, got \(error)", file: file, line: line)
    }
  }

  func testEveryOptionInTheOrderTheCompanionReads() async throws {
    let header = try await read([Self.destination, Self.nameHint, Self.makeDebuggable, Self.overrideModificationTime, Self.skipSigningBundles, Self.link, Self.zstd, Self.data])
    XCTAssertEqual(header.destination, .dsym)
    XCTAssertEqual(header.nameHint, "A")
    XCTAssertTrue(header.makeDebuggable)
    XCTAssertTrue(header.overrideModificationTime)
    XCTAssertTrue(header.skipSigningBundles)
    XCTAssertEqual(header.linkDsymToBundle?.bundleID, "com.example.app")
    XCTAssertEqual(header.compression, .ZSTD)
    XCTAssertEqual(header.payload.data, Data([1, 2, 3]))
  }

  func testAnUndeclaredCompressionIsGzip() async throws {
    let header = try await read([Self.destination, Self.data])
    XCTAssertNil(header.nameHint)
    XCTAssertFalse(header.makeDebuggable)
    XCTAssertNil(header.linkDsymToBundle)
    XCTAssertEqual(header.compression, .GZIP)
  }

  func testAStreamThatDoesNotStartWithADestination() async {
    await assertRejected([Self.nameHint, Self.destination, Self.data], .failedPrecondition, "Expected destination as first request in stream")
  }

  func testCompressionBeforeTheLink() async throws {
    let header = try await read([Self.destination, Self.zstd, Self.link, Self.data])
    XCTAssertEqual(header.linkDsymToBundle?.bundleID, "com.example.app")
    XCTAssertEqual(header.compression, .ZSTD)
    XCTAssertEqual(header.payload.data, Data([1, 2, 3]))
  }

  func testOptionsOutOfTheCompanionsOrder() async throws {
    var header = try await read([Self.destination, Self.link, Self.nameHint, Self.data])
    XCTAssertEqual(header.linkDsymToBundle?.bundleID, "com.example.app")
    XCTAssertEqual(header.nameHint, "A")
    header = try await read([Self.destination, Self.skipSigningBundles, Self.makeDebuggable, Self.data])
    XCTAssertTrue(header.skipSigningBundles)
    XCTAssertTrue(header.makeDebuggable)
  }

  func testARepeatedOption() async {
    await assertRejected([Self.destination, Self.nameHint, Self.nameHint, Self.data], .invalidArgument, "Repeated name_hint in install request stream")
  }

  func testARepeatedCompression() async {
    await assertRejected([Self.destination, Self.zstd, Self.zstd, Self.data], .invalidArgument, "Repeated compression in install request stream")
  }

  func testAStreamWithoutAPayload() async {
    await assertRejected([Self.destination, Self.nameHint], .invalidArgument, "Stream ended")
  }
}
