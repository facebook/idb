/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation

@objc final class FBiOSTargetStateChangeNotifier: NSObject, FBiOSTargetSetDelegate {

  private let filePath: String?
  private let targetSets: [FBiOSTargetSet]
  private let logger: FBControlCoreLogger
  private var current: [String: FBiOSTargetDescription]
  private let finished: FBMutableFuture<NSNull>

  // MARK: Initializers

  @objc static func notifierToFilePath(_ filePath: String, withTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) -> FBFuture<FBiOSTargetStateChangeNotifier> {
    if targetSets.isEmpty {
      return unsafeBitCast(FBIDBError.describe("Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor").failFuture() as FBFuture<AnyObject>, to: FBFuture<FBiOSTargetStateChangeNotifier>.self)
    }

    let didCreateFile = FileManager.default.createFile(
      atPath: filePath,
      contents: "[]".data(using: .utf8),
      attributes: [.posixPermissions: NSNumber(value: Int16(0o666))]
    )

    if !didCreateFile {
      return unsafeBitCast(FBIDBError.describe("Failed to create local targets file: \(filePath) \(String(cString: strerror(errno)))").failFuture() as FBFuture<AnyObject>, to: FBFuture<FBiOSTargetStateChangeNotifier>.self)
    }

    let notifier = FBiOSTargetStateChangeNotifier(filePath: filePath, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return FBFuture(result: notifier)
  }

  @objc static func notifierToStdOut(withTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) -> FBFuture<FBiOSTargetStateChangeNotifier> {
    if targetSets.isEmpty {
      return unsafeBitCast(FBIDBError.describe("Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor").failFuture() as FBFuture<AnyObject>, to: FBFuture<FBiOSTargetStateChangeNotifier>.self)
    }

    let notifier = FBiOSTargetStateChangeNotifier(filePath: nil, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return FBFuture(result: notifier)
  }

  private init(filePath: String?, targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) {
    self.filePath = filePath
    self.targetSets = targetSets
    self.logger = logger
    self.current = [:]
    self.finished = FBMutableFuture<NSNull>()
    super.init()
  }

  // MARK: Public

  @objc func startNotifier() -> FBFuture<NSNull> {
    for targetSet in targetSets {
      for target in targetSet.allTargetInfos {
        current[target.uniqueIdentifier] = FBiOSTargetDescription(target: target)
      }
    }
    if !writeTargets() {
      return unsafeBitCast(finished, to: FBFuture<NSNull>.self)
    }
    // If we're writing to a file, we also need to signal to stdout on the first update
    if filePath != nil {
      if let jsonOutput = try? JSONSerialization.data(withJSONObject: ["report_initial_state": true]) {
        var readyOutput = Data(jsonOutput)
        if let newline = "\n".data(using: .utf8) {
          readyOutput.append(newline)
        }
        readyOutput.withUnsafeBytes { bytes in
          _ = Darwin.write(STDOUT_FILENO, bytes.baseAddress!, bytes.count)
        }
        fflush(stdout)
      }
    }

    return FBFuture<NSNull>.empty()
  }

  @objc var notifierDone: FBFuture<NSNull> {
    return unsafeBitCast(finished, to: FBFuture<NSNull>.self)
  }

  // MARK: Private

  @discardableResult
  private func writeTargets() -> Bool {
    var jsonArray: [[String: Any]] = []
    for target in current.values {
      jsonArray.append(target.asJSON)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: jsonArray) else {
      finished.resolveWithError(FBIDBError.describe("error writing update to consumer").build())
      return false
    }
    if let filePath {
      return writeTargetsData(data, toFilePath: filePath)
    } else {
      return writeTargetsDataToStdOut(data)
    }
  }

  private func writeTargetsData(_ data: Data, toFilePath filePath: String) -> Bool {
    do {
      try (data as NSData).write(toFile: filePath, options: .atomic)
      return true
    } catch {
      logger.log("Failed writing updates \(error)")
      finished.resolveWithError(FBIDBError.describe("Failed writing updates \(error)").build())
      return false
    }
  }

  private func writeTargetsDataToStdOut(_ data: Data) -> Bool {
    data.withUnsafeBytes { bytes in
      _ = Darwin.write(STDOUT_FILENO, bytes.baseAddress!, bytes.count)
    }
    let newline = FBDataBuffer.newlineTerminal()
    newline.withUnsafeBytes { bytes in
      _ = Darwin.write(STDOUT_FILENO, bytes.baseAddress!, bytes.count)
    }
    fflush(stdout)
    return true
  }

  // MARK: FBiOSTargetSetDelegate

  func targetAdded(_ targetInfo: FBiOSTargetInfo, in targetSet: FBiOSTargetSet) {
    current[targetInfo.uniqueIdentifier] = FBiOSTargetDescription(target: targetInfo)
    writeTargets()
  }

  func targetRemoved(_ targetInfo: FBiOSTargetInfo, in targetSet: FBiOSTargetSet) {
    current.removeValue(forKey: targetInfo.uniqueIdentifier)
    writeTargets()
  }

  func targetUpdated(_ targetInfo: FBiOSTargetInfo, in targetSet: FBiOSTargetSet) {
    current[targetInfo.uniqueIdentifier] = FBiOSTargetDescription(target: targetInfo)
    writeTargets()
  }
}
