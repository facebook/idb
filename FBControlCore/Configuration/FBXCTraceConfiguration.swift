/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public let DefaultXCTraceRecordOperationTimeLimit: TimeInterval = 4 * 60 * 60 // 4h
public let DefaultXCTraceRecordStopTimeout: TimeInterval = 600

public struct FBXCTraceRecordConfiguration {

  public let templateName: String
  public let timeLimit: TimeInterval
  public let package: String?
  public let allProcesses: Bool
  public let processToAttach: String?
  public let processToLaunch: String?
  public let launchArgs: [String]?
  public let targetStdin: String?
  public let targetStdout: String?
  public let processEnv: [String: String]?
  public let shim: FBXCTestShimConfiguration?

  public init(templateName: String, timeLimit: TimeInterval, package: String?, allProcesses: Bool, processToAttach: String?, processToLaunch: String?, launchArgs: [String]?, targetStdin: String?, targetStdout: String?, processEnv: [String: String]?, shim: FBXCTestShimConfiguration?) {
    self.templateName = templateName
    self.timeLimit = timeLimit
    self.package = package
    self.allProcesses = allProcesses
    self.processToAttach = processToAttach
    self.processToLaunch = processToLaunch
    self.launchArgs = launchArgs
    self.targetStdin = targetStdin
    self.targetStdout = targetStdout
    self.processEnv = processEnv
    self.shim = shim
  }

  func withShim(_ shim: FBXCTestShimConfiguration) -> FBXCTraceRecordConfiguration {
    FBXCTraceRecordConfiguration(templateName: templateName, timeLimit: timeLimit, package: package, allProcesses: allProcesses, processToAttach: processToAttach, processToLaunch: processToLaunch, launchArgs: launchArgs, targetStdin: targetStdin, targetStdout: targetStdout, processEnv: processEnv, shim: shim)
  }
}

// MARK: - CustomStringConvertible

extension FBXCTraceRecordConfiguration: CustomStringConvertible {

  public var description: String {
    let launchArgsDesc = launchArgs.map { FBCollectionInformation.oneLineDescription(from: $0) } ?? "nil"
    let processEnvDesc = processEnv.map { FBCollectionInformation.oneLineDescription(from: $0) } ?? "nil"
    return "xctrace record: template \(templateName) | duration \(timeLimit) | process to launch \(processToLaunch ?? "nil") | process to attach \(processToAttach ?? "nil") | package \(package ?? "nil") | target stdin \(targetStdin ?? "nil") | target stdout \(targetStdout ?? "nil") | target arguments \(launchArgsDesc) | target environment \(processEnvDesc) | record all processes \(allProcesses ? "Yes" : "No")"
  }
}
