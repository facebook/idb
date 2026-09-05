/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBCrashLogStoreTests: XCTestCase {

  private var directory: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("crash_store_\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let directory, FileManager.default.fileExists(atPath: directory) {
      try FileManager.default.removeItem(atPath: directory)
    }
    directory = nil
    try super.tearDownWithError()
  }

  // MARK: - Ingestion

  func testIngestCrashLogData_WhenDataIsParsable_WritesItIntoTheStoreDirectory() throws {
    let store = makeStore()

    let ingested = store.ingestCrashLogData(try assetsdCrashData(), name: "assetsd.crash")

    let ingestedCrashLog = try XCTUnwrap(ingested, "Parsable crash log data should be ingested")
    XCTAssertEqual(ingestedCrashLog.identifier, "assetsd")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent("assetsd.crash")),
      "Ingested crash log data should be written into the store's directory")
  }

  func testIngestCrashLogData_WhenNameWasAlreadyIngested_ReturnsNil() throws {
    let store = makeStore()
    let data = try assetsdCrashData()

    XCTAssertNotNil(store.ingestCrashLogData(data, name: "assetsd.crash"))

    XCTAssertNil(
      store.ingestCrashLogData(data, name: "assetsd.crash"),
      "Re-ingesting an already-ingested name should be a no-op")
  }

  // MARK: - Delivery

  func testNextCrashLog_WhenMatchingCrashLogIsIngested_DeliversIt() async throws {
    let store = makeStore()
    let next = Task { try await store.nextCrashLog(forMatchingPredicate: FBCrashLogInfo.predicate(forIdentifier: "assetsd")) }
    defer { next.cancel() }

    let ingester = ingestRepeatedly(try assetsdCrashData(), into: store, named: "assetsd")
    defer { ingester.cancel() }

    let delivered = try await next.value

    XCTAssertEqual(delivered.identifier, "assetsd", "The delivered crash log should be the one matching the predicate")
  }

  func testNextCrashLog_WhenIngestedCrashLogDoesNotMatch_SkipsItAndWaitsForOneThatDoes() async throws {
    let store = makeStore()
    let next = Task { try await store.nextCrashLog(forMatchingPredicate: FBCrashLogInfo.predicate(forIdentifier: "assetsd")) }
    defer { next.cancel() }

    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertNotNil(
      store.ingestCrashLogData(try tableSearchCrashData(), name: "tablesearch.crash"),
      "The non-matching crash log should still be ingested")

    let ingester = ingestRepeatedly(try assetsdCrashData(), into: store, named: "assetsd")
    defer { ingester.cancel() }

    let delivered = try await next.value

    XCTAssertEqual(delivered.identifier, "assetsd", "A crash log not matching the predicate should not resolve the wait")
  }

  // MARK: - Helpers

  /// Ingests `data` repeatedly under distinct names until cancelled. The store registers its
  /// notification observer asynchronously, so a single ingest can be posted before the observer
  /// exists and be missed; identical names are deduplicated and post nothing, so each retry
  /// needs a fresh name.
  private func ingestRepeatedly(_ data: Data, into store: FBCrashLogStore, named name: String) -> Task<Void, Never> {
    Task {
      for attempt in 0..<50 {
        if Task.isCancelled { return }
        _ = store.ingestCrashLogData(data, name: "\(name)_\(attempt).crash")
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
    }
  }

  private func makeStore() -> FBCrashLogStore {
    FBCrashLogStore.store(forDirectories: [directory], logger: FBControlCoreLoggerDouble())
  }

  private func assetsdCrashData() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: TestFixtures.assetsdCrashPathWithCustomDeviceSet))
  }

  private func tableSearchCrashData() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: TestFixtures.appCrashPathWithDefaultDeviceSet))
  }
}
