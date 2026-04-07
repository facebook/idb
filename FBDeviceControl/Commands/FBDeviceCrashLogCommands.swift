// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

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

  // MARK: - FBCrashLogCommands

  public func notify(ofCrash predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    ingestAllCrashLogs(useCache: false)
    return store.nextCrashLog(forMatchingPredicate: predicate)
  }

  public func crashes(_ predicate: NSPredicate, useCache: Bool) -> FBFuture<NSArray> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (ingestAllCrashLogs(useCache: useCache)
      .onQueue(
        device.workQueue,
        map: { _ -> AnyObject in
          return self.store.ingestedCrashLogs(matchingPredicate: predicate) as NSArray
        })) as! FBFuture<NSArray>
  }

  public func pruneCrashes(_ predicate: NSPredicate) -> FBFuture<NSArray> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    let logger = device.logger?.withName("crash_remove")
    return
      (ingestAllCrashLogs(useCache: true)
      .onQueue(
        device.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          let pruned = self.store.pruneCrashLogs(matchingPredicate: predicate)
          let names = (pruned as NSArray).value(forKeyPath: "name") as! [Any]
          logger?.log("Pruned \(FBCollectionInformation.oneLineDescription(from: names)) logs from local cache")
          return self.removeCrashLogsFromDevice(pruned, logger: logger) as! FBFuture<AnyObject>
        })) as! FBFuture<NSArray>
  }

  public func crashLogFiles() -> FBFutureContext<any FBFileContainerProtocol> {
    guard let device = device else {
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

  // MARK: - Private

  @discardableResult
  private func ingestAllCrashLogs(useCache: Bool) -> FBFuture<NSArray> {
    if hasPerformedInitialIngestion && useCache {
      return FBFuture(result: NSArray())
    }

    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }

    let logger = device.logger
    return
      (moveCrashReports()
      .onQueue(
        device.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          return
            (self.crashReportFileConnection()
            .onQueue(
              device.workQueue,
              pop: { afc -> FBFuture<AnyObject> in
                if !self.hasPerformedInitialIngestion {
                  self.store.ingestAllExistingInDirectory()
                  self.hasPerformedInitialIngestion = true
                }
                do {
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
                  return FBFuture(result: crashes as NSArray as AnyObject)
                } catch {
                  return FBFuture(error: error)
                }
              }))
        })) as! FBFuture<NSArray>
  }

  private func removeCrashLogsFromDevice(_ crashesToRemove: [FBCrashLogInfo], logger: (any FBControlCoreLogger)?) -> FBFuture<NSArray> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (crashReportFileConnection()
      .onQueue(
        device.workQueue,
        pop: { afc -> FBFuture<AnyObject> in
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
          return FBFuture(result: removed as NSArray as AnyObject)
        })) as! FBFuture<NSArray>
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

  private func moveCrashReports() -> FBFuture<NSString> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (device
      .startService(CrashReportMoverService)
      .onQueue(
        device.asyncQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            let data = try connection.receive(4)
            guard let response = String(data: data, encoding: .ascii) else {
              return FBDeviceControlError()
                .describe("Failed to decode pingback from \(CrashReportMoverService)")
                .failFuture()
            }
            if response != PingSuccess {
              return FBDeviceControlError()
                .describe("Pingback from \(CrashReportMoverService) is '\(response)' not '\(PingSuccess)'")
                .failFuture()
            }
            return FBFuture(result: response as NSString as AnyObject)
          } catch {
            return FBDeviceControlError()
              .describe("Failed to get pingback from \(CrashReportMoverService)")
              .caused(by: error)
              .failFuture()
          }
        })) as! FBFuture<NSString>
  }

  private func crashReportFileConnection() -> FBFutureContext<FBAFCConnection> {
    guard let device = device else {
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
