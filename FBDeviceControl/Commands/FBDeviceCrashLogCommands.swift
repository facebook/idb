/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_cast

private let CrashReportMoverService = "com.apple.crashreportmover"
private let CrashReportCopyService = "com.apple.crashreportcopymobile"
private let PingSuccess = "ping"

@objc(FBDeviceCrashLogCommands)
public class FBDeviceCrashLogCommands: NSObject, FBCrashLogCommands {
  private weak var device: FBDevice?
  private let store: FBCrashLogStore
  private var hasPerformedInitialIngestion: Bool = false

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    let storeDirectory = (target.auxillaryDirectory as NSString).appendingPathComponent("crash_store")
    let store = FBCrashLogStore.store(forDirectories: [storeDirectory], logger: target.logger!)
    return self.init(device: target as! FBDevice, store: store)
  }

  required init(device: FBDevice, store: FBCrashLogStore) {
    self.device = device
    self.store = store
    super.init()
  }

  // MARK: - FBCrashLogCommands (legacy FBFuture entry points)

  @objc(notifyOfCrash:)
  public func notifyOfCrash(_ predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    // Set up the notification listener first, then kick off ingestion as a
    // fire-and-forget background job. Matches the legacy ordering where the
    // listener is registered before the ingestion future resolves.
    let next = store.nextCrashLog(forMatchingPredicate: predicate)
    _ = fbFutureFromAsync { [self] in
      try await ingestAllCrashLogsAsync(useCache: false) as NSArray
    }
    return next
  }

  public func crashes(_ predicate: NSPredicate, useCache: Bool) -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await crashesAsync(predicate, useCache: useCache) as NSArray
    }
  }

  public func pruneCrashes(_ predicate: NSPredicate) -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await pruneCrashesAsync(predicate) as NSArray
    }
  }

  public func crashLogFiles() -> FBFutureContext<any FBFileContainerProtocol> {
    guard let device else {
      return FBDeviceControlError().describe("Device is nil").failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
    }
    return
      (crashReportFileConnection()
      .onQueue(
        device.asyncQueue,
        pend: { connection -> FBFuture<AnyObject> in
          return FBFuture(result: FBDeviceFileContainer(afcConnection: connection, queue: device.asyncQueue) as AnyObject)
        })) as! FBFutureContext<any FBFileContainerProtocol>
  }

  // MARK: - Async

  fileprivate func crashesAsync(_ predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    guard device != nil else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    _ = try await ingestAllCrashLogsAsync(useCache: useCache)
    return store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  fileprivate func pruneCrashesAsync(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let logger = device.logger?.withName("crash_remove")
    _ = try await ingestAllCrashLogsAsync(useCache: true)
    let pruned = store.pruneCrashLogs(matchingPredicate: predicate)
    let names = (pruned as NSArray).value(forKeyPath: "name") as! [Any]
    logger?.log("Pruned \(FBCollectionInformation.oneLineDescription(from: names)) logs from local cache")
    return try await removeCrashLogsFromDeviceAsync(pruned, logger: logger)
  }

  // MARK: - Private

  @discardableResult
  private func ingestAllCrashLogsAsync(useCache: Bool) async throws -> [FBCrashLogInfo] {
    if hasPerformedInitialIngestion && useCache {
      return []
    }
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let logger = device.logger
    _ = try await moveCrashReportsAsync()
    return try await withFBFutureContext(crashReportFileConnection()) { afc in
      if !self.hasPerformedInitialIngestion {
        self.store.ingestAllExistingInDirectory()
        self.hasPerformedInitialIngestion = true
      }
      let paths = try afc.contents(ofDirectory: ".")
      var crashes: [FBCrashLogInfo] = []
      for path in paths {
        do {
          let crash = try self.crashLogInfo(afc: afc, path: path)
          crashes.append(crash)
        } catch {
          logger?.log("Failed to ingest crash log \(path): \(error)")
        }
      }
      return crashes
    }
  }

  private func removeCrashLogsFromDeviceAsync(_ crashesToRemove: [FBCrashLogInfo], logger: (any FBControlCoreLogger)?) async throws -> [FBCrashLogInfo] {
    guard device != nil else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(crashReportFileConnection()) { afc in
      var removed: [FBCrashLogInfo] = []
      for crash in crashesToRemove {
        do {
          try afc.removePath(crash.name, recursively: false)
          logger?.log("Crash \(crash.name) removed from device")
          removed.append(crash)
        } catch {
          logger?.log("Crash \(crash.name) could not be removed from device: \(error)")
        }
      }
      return removed
    }
  }

  private func crashLogInfo(afc: FBAFCConnection, path: String) throws -> FBCrashLogInfo {
    let name = path
    if let existing = store.ingestedCrashLog(withName: path) {
      device?.logger?.log("No need to re-ingest \(path)")
      return existing
    }
    let data = try afc.contents(ofPath: path)
    guard let crash = store.ingestCrashLogData(data, name: name) else {
      throw NSError(domain: FBDeviceControlErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to ingest crash log data for \(name)"])
    }
    return crash
  }

  private func moveCrashReportsAsync() async throws -> String {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.startService(CrashReportMoverService)) { connection in
      let data: Data
      do {
        data = try connection.receive(4)
      } catch {
        throw FBDeviceControlError()
          .describe("Failed to get pingback from \(CrashReportMoverService)")
          .caused(by: error)
          .build()
      }
      guard let response = String(data: data, encoding: .ascii) else {
        throw FBDeviceControlError()
          .describe("Failed to decode pingback from \(CrashReportMoverService)")
          .build()
      }
      if response != PingSuccess {
        throw FBDeviceControlError()
          .describe("Pingback from \(CrashReportMoverService) is '\(response)' not '\(PingSuccess)'")
          .build()
      }
      return response
    }
  }

  private func crashReportFileConnection() -> FBFutureContext<FBAFCConnection> {
    guard let device else {
      return FBDeviceControlError().describe("Device is nil").failFutureContext() as! FBFutureContext<FBAFCConnection>
    }
    return
      device
      .startService(CrashReportCopyService)
      .onQueue(
        device.workQueue,
        push: { connection -> FBFutureContext<AnyObject> in
          return FBAFCConnection.afc(from: connection, calls: FBAFCConnection.defaultCalls, logger: device.logger!, queue: device.workQueue) as! FBFutureContext<AnyObject>
        }) as! FBFutureContext<FBAFCConnection>
  }
}
