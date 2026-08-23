/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import FBControlCore
import Foundation

/// The ways target-state notification can fail, as data rather than assembled strings.
enum FBiOSTargetStateChangeNotifierError: Error {
  case noTargetSets
  case targetsFileCreationFailed(path: String, message: String)
  case initialStateWriteFailed
  case updateSerializationFailed
  case updateWriteFailed(underlying: Error)
}

extension FBiOSTargetStateChangeNotifierError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .noTargetSets:
      return "Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor"
    case let .targetsFileCreationFailed(path, message):
      return "Failed to create local targets file: \(path) \(message)"
    case .initialStateWriteFailed:
      return "Failed to write the initial target state"
    case .updateSerializationFailed:
      return "error writing update to consumer"
    case let .updateWriteFailed(underlying):
      return "Failed writing updates \(underlying)"
    }
  }
}

final class FBiOSTargetStateChangeNotifier: NSObject, FBiOSTargetSetDelegate {

  private let filePath: String?
  private let targetSets: [FBiOSTargetSet]
  private let logger: FBControlCoreLogger
  private var current: [String: FBiOSTargetDescription]
  private let donePromise = AsyncPromise<Void>()

  // MARK: Initializers

  static func notifierToFilePath(_ filePath: String, withTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTargetStateChangeNotifier {
    if targetSets.isEmpty {
      throw FBiOSTargetStateChangeNotifierError.noTargetSets
    }

    let didCreateFile = FileManager.default.createFile(
      atPath: filePath,
      contents: "[]".data(using: .utf8),
      attributes: [.posixPermissions: NSNumber(value: Int16(0o666))]
    )

    if !didCreateFile {
      throw FBiOSTargetStateChangeNotifierError.targetsFileCreationFailed(path: filePath, message: String(cString: strerror(errno)))
    }

    let notifier = FBiOSTargetStateChangeNotifier(filePath: filePath, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return notifier
  }

  static func notifierToStdOut(withTargetSets targetSets: [FBiOSTargetSet], logger: FBControlCoreLogger) throws -> FBiOSTargetStateChangeNotifier {
    if targetSets.isEmpty {
      throw FBiOSTargetStateChangeNotifierError.noTargetSets
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
      throw FBiOSTargetStateChangeNotifierError.initialStateWriteFailed
    }
    // If we're writing to a file, we also need to signal to stdout on the first update
    if filePath != nil {
      if let jsonOutput = try? JSONSerialization.data(withJSONObject: ["report_initial_state": true]) {
        var readyOutput = Data(jsonOutput)
        if let newline = "\n".data(using: .utf8) {
          readyOutput.append(newline)
        }
        writeToStandardOutput(readyOutput)
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
      donePromise.fail(FBiOSTargetStateChangeNotifierError.updateSerializationFailed)
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
      donePromise.fail(FBiOSTargetStateChangeNotifierError.updateWriteFailed(underlying: error))
      return false
    }
  }

  private func writeTargetsDataToStdOut(_ data: Data) -> Bool {
    writeToStandardOutput(data)
    writeToStandardOutput(FBDataBuffer.newlineTerminal())
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
