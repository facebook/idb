/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let FBCrashLogAppeared = NSNotification.Name("FBCrashLogAppeared")

public final class CrashLogStore {

  private let directories: [String]
  private let logger: any FBControlCoreLogger
  private let ingestedCrashLogs: NSMutableDictionary
  private let queue: DispatchQueue

  public class func store(forDirectories directories: [String], logger: any FBControlCoreLogger) -> Self {
    return self.init(directories: directories, logger: logger)
  }

  required init(directories: [String], logger: any FBControlCoreLogger) {
    self.directories = directories
    self.logger = logger
    self.ingestedCrashLogs = NSMutableDictionary()
    self.queue = DispatchQueue(label: "com.facebook.fbcontrolcore.crash_store")
  }

  // MARK: - Ingestion

  @discardableResult public func ingestAllExistingInDirectory() -> [CrashLogInfo] {
    var ingested: [CrashLogInfo] = []
    for directory in directories {
      let crashLogs = ingestCrashLogInDirectory(directory)
      ingested.append(contentsOf: crashLogs)
    }
    return ingested
  }

  func ingestCrashLog(atPath path: String) -> CrashLogInfo? {
    if hasIngestedCrashLog(withName: (path as NSString).lastPathComponent) {
      return nil
    }
    guard let crashLog = try? CrashLogInfo.fromCrashLog(atPath: path) else {
      logger.log("Could not obtain crash info for \(path)")
      return nil
    }
    return ingestCrashLog(crashLog)
  }

  public func ingestCrashLogData(_ data: Data, name: String) -> CrashLogInfo? {
    if hasIngestedCrashLog(withName: name) {
      return nil
    }
    if !CrashLogInfo.isParsableCrashLog(data) {
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

  func removeCrashLog(atPath path: String) -> CrashLogInfo? {
    let key = (path as NSString).lastPathComponent
    guard let crashLog = ingestedCrashLog(withName: key) else {
      return nil
    }
    ingestedCrashLogs.removeObject(forKey: key)
    return crashLog
  }

  // MARK: - Fetching

  public func ingestedCrashLog(withName name: String) -> CrashLogInfo? {
    return ingestedCrashLogs[name] as? CrashLogInfo
  }

  func allIngestedCrashLogs() -> [CrashLogInfo] {
    return ingestedCrashLogs.allValues.compactMap { $0 as? CrashLogInfo }
  }

  public func nextCrashLog(forMatchingPredicate predicate: NSPredicate) async throws -> CrashLogInfo {
    let holder = ObserverHolder()
    nonisolated(unsafe) let predicateRef = predicate
    let box = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CrashLogResultBox, Error>) in
        holder.observer = NotificationCenter.default.addObserver(
          forName: FBCrashLogAppeared,
          object: nil,
          queue: .main
        ) { notification in
          guard let crashLog = notification.object as? CrashLogInfo else { return }
          if !predicateRef.evaluate(with: crashLog) { return }
          if let obs = holder.observer {
            NotificationCenter.default.removeObserver(obs)
            holder.observer = nil
          }
          continuation.resume(returning: CrashLogResultBox(crashLog))
        }
      }
    } onCancel: {
      if let obs = holder.observer {
        NotificationCenter.default.removeObserver(obs)
      }
    }
    return box.value
  }

  public func ingestedCrashLogs(matchingPredicate predicate: NSPredicate) -> [CrashLogInfo] {
    return allIngestedCrashLogs().filter(predicate.evaluate(with:))
  }

  public func pruneCrashLogs(matchingPredicate predicate: NSPredicate) -> [CrashLogInfo] {
    var keys: [String] = []
    var crashLogs: [CrashLogInfo] = []
    for crashLog in allIngestedCrashLogs() {
      if !predicate.evaluate(with: crashLog) {
        continue
      }
      keys.append(crashLog.name)
      crashLogs.append(crashLog)
    }
    ingestedCrashLogs.removeObjects(forKeys: keys)
    return crashLogs
  }

  private func hasIngestedCrashLog(withName key: String) -> Bool {
    return ingestedCrashLogs[key] != nil
  }

  private func ingestCrashLog(_ crashLog: CrashLogInfo) -> CrashLogInfo {
    logger.log("Ingesting Crash Log \(crashLog)")
    ingestedCrashLogs[crashLog.name] = crashLog
    NotificationCenter.default.post(name: FBCrashLogAppeared, object: crashLog)
    return crashLog
  }

  private class ObserverHolder: @unchecked Sendable {
    var observer: NSObjectProtocol?
  }

  private final class CrashLogResultBox: @unchecked Sendable {
    let value: CrashLogInfo
    init(_ value: CrashLogInfo) { self.value = value }
  }

  private func ingestCrashLogInDirectory(_ directory: String) -> [CrashLogInfo] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
      return []
    }
    var ingested: [CrashLogInfo] = []
    for path in contents {
      if let crash = ingestCrashLog(atPath: (directory as NSString).appendingPathComponent(path)) {
        ingested.append(crash)
      }
    }
    return ingested
  }
}
