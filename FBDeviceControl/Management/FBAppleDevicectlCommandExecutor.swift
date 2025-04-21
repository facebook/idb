/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public class FBAppleDevicectlCommandExecutor: NSObject {

  let logger: FBControlCoreLogger?
  let device: FBDevice

  @objc public init(device: FBDevice) {
    logger = device.logger?.withName("devicectl")
    self.device = device
    super.init()
  }

  @objc public func taskBuilder(arguments: [String]) -> FBProcessBuilder<NSNull, NSString, NSString> {
    let derivedArgs = ["devicectl"] + arguments
    return FBProcessBuilder<NSNull, NSString, NSString>.withLaunchPath("/usr/bin/xcrun", arguments: derivedArgs)
      .withStdOutInMemoryAsString()
      .withStdErrInMemoryAsString()
      .withTaskLifecycleLogging(to: logger)
  }
}

public extension FBAppleDevicectlCommandExecutor {
  @objc func launchApplication(configuration: FBApplicationLaunchConfiguration) -> FBFuture<NSNumber> {
    do {
      let tmpPath = try FileManager.default.temporaryFile(extension: "json")
      let tmpPathStr: String
      if #available(macOS 13.0, *) {
        tmpPathStr = tmpPath.path()
      } else {
        tmpPathStr = tmpPath.path
      }
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

      let builder = taskBuilder(arguments: arguments)

      guard
        let future = builder.runUntilCompletion(withAcceptableExitCodes: nil)
          .onQueue(
            device.asyncQueue,
            fmap: { task in
              if task.exitCode.result?.intValue != 0 {
                return FBControlCoreError.describe("devicectl failed with exit code \(task.exitCode.result.flatMap(String.init) ?? "<nil>")\narguments: \(FBCollectionInformation.oneLineDescription(from: arguments))\n\(task.stdOut ?? "")\n\(task.stdErr ?? "")")
                  .failFuture()
              }
              do {
                let data = try Data(contentsOf: tmpPath)
                let info = try JSONDecoder().decode(DevicectlProcInfo.self, from: data)
                return FBFuture<AnyObject>(result: NSNumber(value: info.result.process.processIdentifier))
              } catch {
                return FBFuture(error: error)
              }
            }) as? FBFuture<NSNumber>
      else {
        assertionFailure("Failed to restore FBFuture generic paramter type after type erasure.")
      }
      return future
    } catch {
      return FBFuture(error: error)
    }
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
