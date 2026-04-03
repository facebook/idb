/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBXCTraceRecordConfiguration)
public final class FBXCTraceRecordConfiguration: NSObject, NSCopying {

  @objc public let templateName: String
  @objc public let timeLimit: TimeInterval
  @objc public let package: String?
  @objc public let allProcesses: Bool
  @objc public let processToAttach: String?
  @objc public let processToLaunch: String?
  @objc public let launchArgs: [String]?
  @objc public let targetStdin: String?
  @objc public let targetStdout: String?
  @objc public let processEnv: [String: String]?
  @objc public let shim: FBXCTestShimConfiguration?

  @objc(RecordWithTemplateName:timeLimit:package:allProcesses:processToAttach:processToLaunch:launchArgs:targetStdin:targetStdout:processEnv:shim:)
  public class func record(withTemplateName templateName: String, timeLimit: TimeInterval, package: String?, allProcesses: Bool, processToAttach: String?, processToLaunch: String?, launchArgs: [String]?, targetStdin: String?, targetStdout: String?, processEnv: [String: String]?, shim: FBXCTestShimConfiguration?) -> FBXCTraceRecordConfiguration {
    return FBXCTraceRecordConfiguration(templateName: templateName, timeLimit: timeLimit, package: package, allProcesses: allProcesses, processToAttach: processToAttach, processToLaunch: processToLaunch, launchArgs: launchArgs, targetStdin: targetStdin, targetStdout: targetStdout, processEnv: processEnv, shim: shim)
  }

  @objc
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
    super.init()
  }

  @objc
  public func withShim(_ shim: FBXCTestShimConfiguration) -> FBXCTraceRecordConfiguration {
    return FBXCTraceRecordConfiguration(templateName: templateName, timeLimit: timeLimit, package: package, allProcesses: allProcesses, processToAttach: processToAttach, processToLaunch: processToLaunch, launchArgs: launchArgs, targetStdin: targetStdin, targetStdout: targetStdout, processEnv: processEnv, shim: shim)
  }

  public override var description: String {
    let launchArgsDesc = launchArgs.map { FBCollectionInformation.oneLineDescription(from: $0) } ?? "nil"
    let processEnvDesc = processEnv.map { FBCollectionInformation.oneLineDescription(from: $0) } ?? "nil"
    return "xctrace record: template \(templateName) | duration \(timeLimit) | process to launch \(processToLaunch ?? "nil") | process to attach \(processToAttach ?? "nil") | package \(package ?? "nil") | target stdin \(targetStdin ?? "nil") | target stdout \(targetStdout ?? "nil") | target arguments \(launchArgsDesc) | target environment \(processEnvDesc) | record all processes \(allProcesses ? "Yes" : "No")"
  }

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }
}
