/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IDBConcurrency

enum TargetStateChangeNotifierError: Error {
  case noTargetSets
  case targetsFileCreationFailed(path: String, message: String)
  case initialStateWriteFailed
  case updateSerializationFailed
  case updateWriteFailed(underlying: Error)
}

extension TargetStateChangeNotifierError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .noTargetSets:
      return "Cannot initialize TargetStateChangeNotifier without any sets to monitor"
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

public final class TargetStateChangeNotifier: TargetSetDelegate {

  private let filePath: String?
  private let targetSets: [TargetSet]
  private let logger: ControlCoreLogger
  private var current: [String: TargetDescription]
  private let donePromise = AsyncPromise<Void>()

  public static func notifierToFilePath(_ filePath: String, withTargetSets targetSets: [TargetSet], logger: ControlCoreLogger) throws -> TargetStateChangeNotifier {
    if targetSets.isEmpty {
      throw TargetStateChangeNotifierError.noTargetSets
    }

    let didCreateFile = FileManager.default.createFile(
      atPath: filePath,
      contents: "[]".data(using: .utf8),
      attributes: [.posixPermissions: NSNumber(value: Int16(0o666))]
    )

    if !didCreateFile {
      throw TargetStateChangeNotifierError.targetsFileCreationFailed(path: filePath, message: String(cString: strerror(errno)))
    }

    let notifier = TargetStateChangeNotifier(filePath: filePath, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return notifier
  }

  public static func notifierToStdOut(withTargetSets targetSets: [TargetSet], logger: ControlCoreLogger) throws -> TargetStateChangeNotifier {
    if targetSets.isEmpty {
      throw TargetStateChangeNotifierError.noTargetSets
    }

    let notifier = TargetStateChangeNotifier(filePath: nil, targetSets: targetSets, logger: logger)
    for targetSet in targetSets {
      targetSet.delegate = notifier
    }
    return notifier
  }

  private init(filePath: String?, targetSets: [TargetSet], logger: ControlCoreLogger) {
    self.filePath = filePath
    self.targetSets = targetSets
    self.logger = logger
    self.current = [:]
  }

  public func startNotifier() throws {
    for targetSet in targetSets {
      for target in targetSet.allTargetInfos {
        current[target.uniqueIdentifier] = TargetDescription(target: target)
      }
    }
    guard writeTargets() else {
      throw TargetStateChangeNotifierError.initialStateWriteFailed
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
  public func waitUntilDone() async throws {
    try await donePromise.value
  }

  @discardableResult
  private func writeTargets() -> Bool {
    var jsonArray: [[String: Any]] = []
    for target in current.values {
      jsonArray.append(target.asJSON)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: jsonArray) else {
      donePromise.fail(TargetStateChangeNotifierError.updateSerializationFailed)
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
      donePromise.fail(TargetStateChangeNotifierError.updateWriteFailed(underlying: error))
      return false
    }
  }

  private func writeTargetsDataToStdOut(_ data: Data) -> Bool {
    writeToStandardOutput(data)
    writeToStandardOutput(DataBuffer.newlineTerminal())
    fflush(stdout)
    return true
  }

  // MARK: - TargetSetDelegate

  public func targetAdded(_ targetInfo: TargetInfo, in targetSet: TargetSet) {
    current[targetInfo.uniqueIdentifier] = TargetDescription(target: targetInfo)
    writeTargets()
  }

  public func targetRemoved(_ targetInfo: TargetInfo, in targetSet: TargetSet) {
    current.removeValue(forKey: targetInfo.uniqueIdentifier)
    writeTargets()
  }

  public func targetUpdated(_ targetInfo: TargetInfo, in targetSet: TargetSet) {
    current[targetInfo.uniqueIdentifier] = TargetDescription(target: targetInfo)
    writeTargets()
  }
}

public final class TargetDescription: TargetInfo {

  public let uniqueIdentifier: String
  public let udid: String
  public let name: String
  public let deviceType: DeviceType
  public let architectures: [Architecture]
  public let osVersion: OSVersion
  public let extendedInformation: [String: Any]
  public let targetType: TargetType
  public let state: TargetState

  private let model: DeviceModel?

  // These values are parsed into TargetDescription in idb/common/types.py, so need to be stable.
  private static let keyModel = "model"
  private static let keyName = "name"
  private static let keyOSVersion = "os_version"
  private static let keyState = "state"
  private static let keyType = "type"
  private static let keyUDID = "udid"

  public init(target: TargetInfo) {
    self.extendedInformation = target.extendedInformation
    self.model = target.deviceType.model
    self.name = target.name
    self.osVersion = target.osVersion
    self.state = target.state
    self.targetType = target.targetType
    self.udid = target.udid
    self.uniqueIdentifier = target.uniqueIdentifier
    self.deviceType = target.deviceType
    self.architectures = target.architectures
  }

  public var asJSON: [String: Any] {
    var representation: [String: Any] = [
      Self.keyModel: model.map { $0.rawValue as Any } ?? NSNull(),
      Self.keyName: name as Any? ?? NSNull(),
      Self.keyOSVersion: osVersion.name.rawValue,
      Self.keyState: state.stateString.rawValue,
      Self.keyType: targetType.stringRepresentation,
      Self.keyUDID: udid as Any? ?? NSNull(),
    ]
    for (key, value) in extendedInformation {
      representation[key] = value
    }
    return representation
  }
}
