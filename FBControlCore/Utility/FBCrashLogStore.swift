/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let FBCrashLogAppeared = NSNotification.Name("FBCrashLogAppeared")

@objc(FBCrashLogStore)
public class FBCrashLogStore: NSObject {

  // MARK: Properties

  private let directories: [String]
  private let logger: any FBControlCoreLogger
  private let ingestedCrashLogs: NSMutableDictionary
  private let queue: DispatchQueue

  // MARK: Initializers

  @objc(storeForDirectories:logger:)
  public class func store(forDirectories directories: [String], logger: any FBControlCoreLogger) -> Self {
    return self.init(directories: directories, logger: logger)
  }

  required init(directories: [String], logger: any FBControlCoreLogger) {
    self.directories = directories
    self.logger = logger
    self.ingestedCrashLogs = NSMutableDictionary()
    self.queue = DispatchQueue(label: "com.facebook.fbcontrolcore.crash_store")
    super.init()
  }

  // MARK: Ingestion

  @discardableResult @objc public func ingestAllExistingInDirectory() -> [FBCrashLogInfo] {
    var ingested: [FBCrashLogInfo] = []
    for directory in directories {
      let crashLogs = ingestCrashLogInDirectory(directory)
      ingested.append(contentsOf: crashLogs)
    }
    return ingested
  }

  @objc(ingestCrashLogAtPath:)
  public func ingestCrashLog(atPath path: String) -> FBCrashLogInfo? {
    if hasIngestedCrashLog(withName: (path as NSString).lastPathComponent) {
      return nil
    }
    guard let crashLog = try? FBCrashLogInfo.fromCrashLog(atPath: path) else {
      logger.log("Could not obtain crash info for \(path)")
      return nil
    }
    return ingestCrashLog(crashLog)
  }

  @objc(ingestCrashLogData:name:)
  public func ingestCrashLogData(_ data: Data, name: String) -> FBCrashLogInfo? {
    if hasIngestedCrashLog(withName: name) {
      return nil
    }
    if !FBCrashLogInfo.isParsableCrashLog(data) {
      return nil
    }
    for directory in directories {
      let destination = (directory as NSString).appendingPathComponent(name)
      if !FileManager.default.fileExists(atPath: directory) {
        if (try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)) == nil {
          continue
        }
      }
      if !(data as NSData).write(toFile: destination, atomically: true) {
        continue
      }
      return ingestCrashLog(atPath: destination)
    }
    return nil
  }

  @objc(removeCrashLogAtPath:)
  public func removeCrashLog(atPath path: String) -> FBCrashLogInfo? {
    let key = (path as NSString).lastPathComponent
    guard let crashLog = ingestedCrashLog(withName: key) else {
      return nil
    }
    ingestedCrashLogs.removeObject(forKey: key)
    return crashLog
  }

  // MARK: Fetching

  @objc(ingestedCrashLogWithName:)
  public func ingestedCrashLog(withName name: String) -> FBCrashLogInfo? {
    return ingestedCrashLogs[name] as? FBCrashLogInfo
  }

  @objc public func allIngestedCrashLogs() -> [FBCrashLogInfo] {
    return ingestedCrashLogs.allValues as! [FBCrashLogInfo]
  }

  @objc(nextCrashLogForMatchingPredicate:)
  public func nextCrashLog(forMatchingPredicate predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    let result = FBFuture<AnyObject>.onQueue(queue, resolve: {
      return FBCrashLogStore.oneshotCrashLogNotification(forPredicate: predicate, queue: self.queue)
    })
    return unsafeBitCast(result, to: FBFuture<FBCrashLogInfo>.self)
  }

  @objc(ingestedCrashLogsMatchingPredicate:)
  public func ingestedCrashLogs(matchingPredicate predicate: NSPredicate) -> [FBCrashLogInfo] {
    return (ingestedCrashLogs.allValues as NSArray).filtered(using: predicate) as! [FBCrashLogInfo]
  }

  @objc(pruneCrashLogsMatchingPredicate:)
  public func pruneCrashLogs(matchingPredicate predicate: NSPredicate) -> [FBCrashLogInfo] {
    var keys: [String] = []
    var crashLogs: [FBCrashLogInfo] = []
    for crashLog in ingestedCrashLogs.allValues as! [FBCrashLogInfo] {
      if !predicate.evaluate(with: crashLog) {
        continue
      }
      keys.append(crashLog.name)
      crashLogs.append(crashLog)
    }
    ingestedCrashLogs.removeObjects(forKeys: keys)
    return crashLogs
  }

  // MARK: Private

  private func hasIngestedCrashLog(withName key: String) -> Bool {
    return ingestedCrashLogs[key] != nil
  }

  private func ingestCrashLog(_ crashLog: FBCrashLogInfo) -> FBCrashLogInfo {
    logger.log("Ingesting Crash Log \(crashLog)")
    ingestedCrashLogs[crashLog.name] = crashLog
    NotificationCenter.default.post(name: FBCrashLogAppeared, object: crashLog)
    return crashLog
  }

  private class ObserverHolder: @unchecked Sendable {
    var observer: NSObjectProtocol?
  }

  private class func oneshotCrashLogNotification(forPredicate predicate: NSPredicate, queue: DispatchQueue) -> FBFuture<AnyObject> {
    let notificationCenter = NotificationCenter.default
    nonisolated(unsafe) let future: FBMutableFuture<AnyObject> = FBMutableFuture()
    nonisolated(unsafe) let predicateRef = predicate
    let holder = ObserverHolder()

    holder.observer = notificationCenter.addObserver(
      forName: FBCrashLogAppeared,
      object: nil,
      queue: .main
    ) { notification in
      guard let crashLog = notification.object as? FBCrashLogInfo else { return }
      if !predicateRef.evaluate(with: crashLog) {
        return
      }
      future.resolve(withResult: crashLog)
      if let obs = holder.observer {
        notificationCenter.removeObserver(obs)
      }
    }

    return future.onQueue(queue, respondToCancellation: {
      if let obs = holder.observer {
        notificationCenter.removeObserver(obs)
      }
      return FBFuture<AnyObject>.empty()
    })
  }

  private func ingestCrashLogInDirectory(_ directory: String) -> [FBCrashLogInfo] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
      return []
    }
    var ingested: [FBCrashLogInfo] = []
    for path in contents {
      if let crash = ingestCrashLog(atPath: (directory as NSString).appendingPathComponent(path)) {
        ingested.append(crash)
      }
    }
    return ingested
  }
}
