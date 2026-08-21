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
  case deviceNil
  case ingestFailed(name: String)
  case pingbackReceiveFailed(service: String, underlying: Error)
  case pingbackNotDecodable(service: String)
  case pingbackUnsuccessful(service: String, response: String, expected: String)
}

extension FBDeviceCrashLogError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .deviceNil:
      return "Device is nil"
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

public class FBDeviceCrashLogCommands: NSObject {
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
    super.init()
  }

  // MARK: - FBCrashLogCommands (legacy FBFuture entry point)

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

  // MARK: - Async

  fileprivate func crashesAsync(_ predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    guard device != nil else {
      throw FBDeviceCrashLogError.deviceNil
    }
    _ = try await ingestAllCrashLogsAsync(useCache: useCache)
    return store.ingestedCrashLogs(matchingPredicate: predicate)
  }

  fileprivate func pruneCrashesAsync(_ predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    guard let device else {
      throw FBDeviceCrashLogError.deviceNil
    }
    let logger = device.logger.withName("crash_remove")
    _ = try await ingestAllCrashLogsAsync(useCache: true)
    let pruned = store.pruneCrashLogs(matchingPredicate: predicate)
    logger.log("Pruned \(FBCollectionInformation.oneLineDescription(from: pruned.map(\.name))) logs from local cache")
    return try await removeCrashLogsFromDeviceAsync(pruned, logger: logger)
  }

  fileprivate func crashLogFilesContext() -> FBFutureContext<FBDeviceFileContainer> {
    guard let device else {
      return FBFutureContext(error: FBDeviceCrashLogError.deviceNil)
    }
    let asyncQueue = device.asyncQueue
    return
      crashReportFileConnection()
      .onQueue(
        asyncQueue,
        pend: { connection -> FBFuture<AnyObject> in
          FBFuture(result: FBDeviceFileContainer(afcConnection: connection, queue: asyncQueue) as AnyObject)
        }
      ).retyped(FBFutureContext<FBDeviceFileContainer>.self)
  }

  // MARK: - Private

  @discardableResult
  private func ingestAllCrashLogsAsync(useCache: Bool) async throws -> [FBCrashLogInfo] {
    if hasPerformedInitialIngestion && useCache {
      return []
    }
    guard let device else {
      throw FBDeviceCrashLogError.deviceNil
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
          logger.log("Failed to ingest crash log \(path): \(error)")
        }
      }
      return crashes
    }
  }

  private func removeCrashLogsFromDeviceAsync(_ crashesToRemove: [FBCrashLogInfo], logger: (any FBControlCoreLogger)?) async throws -> [FBCrashLogInfo] {
    guard device != nil else {
      throw FBDeviceCrashLogError.deviceNil
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
      throw FBDeviceCrashLogError.deviceNil
    }
    return try await withFBFutureContext(device.startService(CrashReportMoverService)) { connection in
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

  private func crashReportFileConnection() -> FBFutureContext<FBAFCConnection> {
    guard let device else {
      return FBFutureContext(error: FBDeviceCrashLogError.deviceNil)
    }
    let workQueue = device.workQueue
    let logger = device.logger
    return
      device
      .startService(CrashReportCopyService)
      .onQueue(
        workQueue,
        push: { connection -> FBFutureContext<AnyObject> in
          FBAFCConnection.afc(from: connection, calls: FBAFCConnection.defaultCalls, logger: logger, queue: workQueue)
            .retyped(FBFutureContext<AnyObject>.self)
        }
      ).retyped(FBFutureContext<FBAFCConnection>.self)
  }
}

// MARK: - FBDevice+CrashLogCommands

extension FBDevice: CrashLogCommands {

  public func crashes(matching predicate: NSPredicate, useCache: Bool) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().crashesAsync(predicate, useCache: useCache)
  }

  public func notifyOfCrash(matching predicate: NSPredicate) async throws -> FBCrashLogInfo {
    let cmds = try crashLogCommands()
    return try await bridgeFBFuture(cmds.notifyOfCrash(predicate))
  }

  public func pruneCrashes(matching predicate: NSPredicate) async throws -> [FBCrashLogInfo] {
    try await crashLogCommands().pruneCrashesAsync(predicate)
  }

  public func withCrashLogFiles<R>(body: (any AsyncFileContainer) async throws -> R) async throws -> R {
    try await withFBFutureContext(crashLogCommands().crashLogFilesContext()) { container in
      try await body(container)
    }
  }
}
