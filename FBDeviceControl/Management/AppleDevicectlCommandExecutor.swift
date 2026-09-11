/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public enum DevicectlError: Error {
  case commandFailed(exitCode: String, arguments: [String], stdOut: String, stdErr: String)
}

extension DevicectlError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .commandFailed(exitCode, arguments, stdOut, stdErr):
      return "devicectl failed with exit code \(exitCode)\narguments: \(CollectionInformation.oneLineDescription(from: arguments))\n\(stdOut)\n\(stdErr)"
    }
  }
}

class AppleDevicectlCommandExecutor {

  let logger: FBControlCoreLogger?
  let device: FBDevice

  init(device: FBDevice) {
    logger = device.logger.withName("devicectl")
    self.device = device
  }

}

extension AppleDevicectlCommandExecutor {
  func launchApplication(configuration: FBApplicationLaunchConfiguration) async throws -> NSNumber {
    let tmpPath = try FileManager.default.temporaryFile(extension: "json")
    let tmpPathStr = tmpPath.path()
    var arguments = [
      "device",
      "process",
      "launch",
      "--device",
      device.udid,
      "--terminate-existing",
      "--json-output",
      tmpPathStr,
    ]
    if !configuration.environment.isEmpty {
      if let envstr = String(
        data: try JSONSerialization.data(withJSONObject: configuration.environment),
        encoding: .utf8)
      {
        arguments += ["--environment-variables", envstr]
      }
    }
    if configuration.waitForDebugger {
      arguments.append("--start-stopped")
    }
    arguments.append(configuration.bundleID)
    arguments += configuration.arguments

    let result = try await Subprocess(executable: "/usr/bin/xcrun", arguments: ["devicectl"] + arguments)
      .run(exitPolicy: .any, logger: logger)
    try result.checkExitedCleanly { code in
      DevicectlError.commandFailed(
        exitCode: String(code),
        arguments: arguments,
        stdOut: result.standardOutput,
        stdErr: result.standardError)
    }
    let data = try Data(contentsOf: tmpPath)
    let info = try JSONDecoder().decode(DevicectlProcInfo.self, from: data)
    return NSNumber(value: info.result.process.processIdentifier)
  }

  private struct DevicectlProcInfo: Decodable {
    struct Result: Decodable {
      struct Process: Decodable {
        var processIdentifier: Int
      }
      var process: Process
    }
    var result: Result
  }
}
