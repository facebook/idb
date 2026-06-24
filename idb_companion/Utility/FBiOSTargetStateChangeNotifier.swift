/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation
import IDBCompanionUtilities

@objc final class FBiOSTargetStateChangeNotifier: NSObject, FBiOSTargetSetDelegate {

  private let filePath: String?
  private let targetSets: [FBiOSTargetSet]
  private let logger: FBControlCoreLogger
  private var current: [String: FBiOSTargetDescription]
  private let donePromise = AsyncPromise<Void>()

  // MARK: Initializers

  static func notifierToFilePath(_ filePath: String, withTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTargetStateChangeNotifier {
    if targetSets.isEmpty {
      throw FBIDBError.describe("Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor").build()
    }

    let didCreateFile = FileManager.default.createFile(
      atPath: filePath,
      contents: "[]".data(using: .utf8),
      attributes: [.posixPermissions: NSNumber(value: Int16(0o666))]
    )

    if !didCreateFile {
      throw FBIDBError.describe("Failed to create local targets file: \(filePath) \(String(cString: strerror(errno)))").build()
    }

    let notifier = FBiOSTargetStateChangeNotifier(filePath: filePath, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return notifier
  }

  static func notifierToStdOut(withTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTargetStateChangeNotifier {
    if targetSets.isEmpty {
      throw FBIDBError.describe("Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor").build()
    }

    let notifier = FBiOSTargetStateChangeNotifier(filePath: nil, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return notifier
  }

  private init(filePath: String?, targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) {
    self.filePath = filePath
    self.targetSets = targetSets
    self.logger = logger
    self.current = [:]
    super.init()
  }

  // MARK: Public

  func startNotifier() throws {
    for targetSet in targetSets {
      for target in targetSet.allTargetInfos {
        current[target.uniqueIdentifier] = FBiOSTargetDescription(target: target)
      }
    }
    guard writeTargets() else {
      throw FBIDBError.describe("Failed to write the initial target state").build()
    }
    // If we're writing to a file, we also need to signal to stdout on the first update
    if filePath != nil {
      if let jsonOutput = try? JSONSerialization.data(withJSONObject: ["report_initial_state": true]) {
        var readyOutput = Data(jsonOutput)
        if let newline = "\n".data(using: .utf8) {
          readyOutput.append(newline)
        }
        readyOutput.withUnsafeBytes { bytes in
          // swiftlint:disable:next force_unwrapping
          _ = Darwin.write(STDOUT_FILENO, bytes.baseAddress!, bytes.count)
        }
        fflush(stdout)
      }
    }
  }

  /// Suspends until the notifier finishes (on a write error) or is cancelled.
  func waitUntilDone() async throws {
    try await donePromise.value
  }

  // MARK: Private

  @discardableResult
  private func writeTargets() -> Bool {
    var jsonArray: [[String: Any]] = []
    for target in current.values {
      jsonArray.append(target.asJSON)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: jsonArray) else {
      donePromise.fail(FBIDBError.describe("error writing update to consumer").build())
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
      donePromise.fail(FBIDBError.describe("Failed writing updates \(error)").build())
      return false
    }
  }

  private func writeTargetsDataToStdOut(_ data: Data) -> Bool {
    data.withUnsafeBytes { bytes in
      // swiftlint:disable:next force_unwrapping
      _ = Darwin.write(STDOUT_FILENO, bytes.baseAddress!, bytes.count)
    }
    let newline = FBDataBuffer.newlineTerminal()
    newline.withUnsafeBytes { bytes in
      // swiftlint:disable:next force_unwrapping
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
