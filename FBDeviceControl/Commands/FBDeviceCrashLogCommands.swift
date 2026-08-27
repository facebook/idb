/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let CrashReportMoverService = "com.apple.crashreportmover"
private let CrashReportCopyService = "com.apple.crashreportcopymobile"
private let PingSuccess = "ping"

/// The ways device crash-log collection can fail, as data rather than assembled strings.
public enum FBDeviceCrashLogError: Error {
  case ingestFailed(name: String)
  case pingbackReceiveFailed(service: String, underlying: Error)
  case pingbackNotDecodable(service: String)
  case pingbackUnsuccessful(service: String, response: String, expected: String)
}

extension FBDeviceCrashLogError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .ingestFailed(name):
      return "Failed to ingest crash log data for \(name)"
    case let .pingbackReceiveFailed(service, _):
      return "Failed to get pingback from \(service)"
    case let .pingbackNotDecodable(service):
      return "Failed to decode pingback from \(service)"
    case let .pingbackUnsuccessful(service, response, expected):
      return "Pingback from \(service) is '\(response)' not '\(expected)'"
    }
  }
}

public class FBDeviceCrashLogCommands {
  private weak var device: FBDevice?
  private let store: FBCrashLogStore
  private var hasPerformedInitialIngestion: Bool = false

  // MARK: - Initializers

  public class func commands(with device: FBDevice) -> FBDeviceCrashLogCommands {
    let storeDirectory = (device.auxillaryDirectory as NSString).appendingPathComponent("crash_store")
    let store = FBCrashLogStore.store(forDirectories: [storeDirectory], logger: device.logger)
    return FBDeviceCrashLogCommands(device: device, store: store)
  }

  init(device: FBDevice, store: FBCrashLogStore) {
    self.device = device
    self.store = store
  }

  // MARK: - Notify

  fileprivate func notifyOfCrashAsync(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    // Start listening for the next matching crash log first, then kick off ingestion as a
    // fire-and-forget background job - the same task ordering the future-based predecessor
    // established.
    // The listener rides fbFutureFromAsync rather than Task: region isolation rejects
    // sending the non-Sendable predicate into a Task closure.
    let next = fbFutureFromAsync { [store] in
      try await store.nextCrashLog(forMatchingPredicate: predicate)
    }
    _ = fbFutureFromAsync { [self] in
      try await ingestAllCrashLogsAsync(useCache: false) as NSArray
    }
    return try await bridgeFBFuture(next)
  }

  // MARK: - Async

  fileprivate func crashesAsync(_ predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    guard device != nil else {
      throw FBDeviceNilError.deviceNil
    }
    _ = try await ingestAllCrashLogsAsync(useCache: useCache)
    return store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  fileprivate func pruneCrashesAsync(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let logger = device.logger.withName("crash_remove")
    _ = try await ingestAllCrashLogsAsync(useCache: true)
    let pruned = store.pruneCrashLogs(matchingPredicate: predicate)
    logger.log("Pruned \(FBCollectionInformation.oneLineDescription(from: pruned.map(\.name))) logs from local cache")
    return try await removeCrashLogsFromDeviceAsync(pruned, logger: logger)
  }

  // MARK: - Private

  @discardableResult
  private func ingestAllCrashLogsAsync(useCache: Bool) async throws -> [FBCrashLogInfo] {
    if hasPerformedInitialIngestion && useCache {
      return []
    }
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let logger = device.logger
    _ = try await moveCrashReportsAsync()
    return try await withCrashReportFileConnection { afc in
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
          logger.log("Failed to ingest crash log \(path): \(error)")
        }
      }
      return crashes
    }
  }

  private func removeCrashLogsFromDeviceAsync(_ crashesToRemove: [FBCrashLogInfo], logger: (any FBControlCoreLogger)?) async throws -> [FBCrashLogInfo] {
    guard device != nil else {
      throw FBDeviceNilError.deviceNil
    }
    return try await withCrashReportFileConnection { afc in
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
      device?.logger.log("No need to re-ingest \(path)")
      return existing
    }
    let data = try afc.contents(ofPath: path)
    guard let crash = store.ingestCrashLogData(data, name: name) else {
      throw FBDeviceCrashLogError.ingestFailed(name: name)
    }
    return crash
  }

  private func moveCrashReportsAsync() async throws -> String {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withServiceConnection(CrashReportMoverService) { connection in
      let data: Data
      do {
        data = try connection.receive(4)
      } catch {
        throw FBDeviceCrashLogError.pingbackReceiveFailed(service: CrashReportMoverService, underlying: error)
      }
      guard let response = String(data: data, encoding: .ascii) else {
        throw FBDeviceCrashLogError.pingbackNotDecodable(service: CrashReportMoverService)
      }
      if response != PingSuccess {
        throw FBDeviceCrashLogError.pingbackUnsuccessful(service: CrashReportMoverService, response: response, expected: PingSuccess)
      }
      return response
    }
  }

  private func withCrashReportFileConnection<T>(_ body: (FBAFCConnection) async throws -> T) async throws -> T {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    return try await device.withAFCConnection(CrashReportCopyService, body)
  }
}

// MARK: - FBDevice+CrashLogCommands

extension FBDevice: CrashLogCommands {

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().crashesAsync(predicate, useCache: useCache)
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    try await crashLogCommands().notifyOfCrashAsync(matching: predicate)
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().pruneCrashesAsync(predicate)
  }

  public func withCrashLogFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    let queue = asyncQueue
    return try await withAFCConnection(CrashReportCopyService) { afc in
      try await body(FBDeviceFileContainer(afcConnection: afc, queue: queue))
    }
  }
}
