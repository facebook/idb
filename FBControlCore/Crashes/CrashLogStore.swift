/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let CrashLogAppeared = NSNotification.Name("CrashLogAppeared")

public final class CrashLogStore {

  private let directories: [String]
  private let logger: any ControlCoreLogger
  private let ingestedCrashLogs: NSMutableDictionary
  private let queue: DispatchQueue

  public class func store(forDirectories directories: [String], logger: any ControlCoreLogger) -> Self {
    return self.init(directories: directories, logger: logger)
  }

  required init(directories: [String], logger: any ControlCoreLogger) {
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

  /// Starts listening for the next crash log matching `predicate` before returning, so one ingested
  /// before `CrashLogListener.next()` is awaited is still delivered.
  public func listenForNextCrashLog(matching predicate: CrashLogPredicate) -> CrashLogListener {
    CrashLogListener(predicate: predicate)
  }

  public func nextCrashLog(forMatchingPredicate predicate: CrashLogPredicate) async throws -> CrashLogInfo {
    try await listenForNextCrashLog(matching: predicate).next()
  }

  public func ingestedCrashLogs(matchingPredicate predicate: CrashLogPredicate) -> [CrashLogInfo] {
    return allIngestedCrashLogs().filter(predicate.matches)
  }

  public func pruneCrashLogs(matchingPredicate predicate: CrashLogPredicate) -> [CrashLogInfo] {
    var keys: [String] = []
    var crashLogs: [CrashLogInfo] = []
    for crashLog in allIngestedCrashLogs() {
      if !predicate.matches(crashLog) {
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
    NotificationCenter.default.post(name: CrashLogAppeared, object: crashLog)
    return crashLog
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

/// Holds the first crash log matching its predicate from the moment it is created, and hands it to
/// the one caller of `next()`.
public final class CrashLogListener: @unchecked Sendable {
  private enum State {
    case listening
    case waiting(CheckedContinuation<CrashLogResultBox, Error>)
    case resolved(Result<CrashLogResultBox, Error>)
    case consumed
  }

  private let lock = NSLock()
  private var state = State.listening
  private var observer: NSObjectProtocol?

  init(predicate: CrashLogPredicate) {
    lock.lock()
    defer { lock.unlock() }
    observer = NotificationCenter.default.addObserver(forName: CrashLogAppeared, object: nil, queue: nil) { [weak self] notification in
      guard let crashLog = notification.object as? CrashLogInfo, predicate.matches(crashLog) else { return }
      self?.resolve(.success(CrashLogResultBox(crashLog)))
    }
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// Returns the first matching crash log, waiting for one if none has appeared yet. Cancellation,
  /// including before the call, throws `CancellationError` unless a crash log has already appeared.
  /// Must be awaited at most once.
  public func next() async throws -> CrashLogInfo {
    let box = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CrashLogResultBox, Error>) in
        lock.lock()
        switch state {
        case .listening:
          state = .waiting(continuation)
          lock.unlock()
        case let .resolved(result):
          state = .consumed
          lock.unlock()
          continuation.resume(with: result)
        case .waiting, .consumed:
          lock.unlock()
          preconditionFailure("CrashLogListener.next() must be awaited at most once")
        }
      }
    } onCancel: {
      resolve(.failure(CancellationError()))
    }
    return box.value
  }

  private func resolve(_ result: Result<CrashLogResultBox, Error>) {
    lock.lock()
    let observer = self.observer
    self.observer = nil
    let continuation: CheckedContinuation<CrashLogResultBox, Error>?
    switch state {
    case .listening:
      state = .resolved(result)
      continuation = nil
    case let .waiting(waiting):
      state = .consumed
      continuation = waiting
    case .resolved, .consumed:
      continuation = nil
    }
    lock.unlock()
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
    continuation?.resume(with: result)
  }
}

private final class CrashLogResultBox: @unchecked Sendable {
  let value: CrashLogInfo
  init(_ value: CrashLogInfo) { self.value = value }
}
