/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class FBXCTraceRecordOperation {

  // MARK: Properties

  public let task: FBSubprocess<AnyObject, AnyObject, AnyObject>
  public let queue: DispatchQueue
  public let traceDir: URL
  public let configuration: FBXCTraceRecordConfiguration
  public let logger: FBControlCoreLogger

  // MARK: Initializers

  public init(task: FBSubprocess<AnyObject, AnyObject, AnyObject>, traceDir: URL, configuration: FBXCTraceRecordConfiguration, queue: DispatchQueue, logger: FBControlCoreLogger) {
    self.task = task
    self.traceDir = traceDir
    self.configuration = configuration
    self.queue = queue
    self.logger = logger
  }

  public class func operation(with target: FBiOSTarget, configuration: FBXCTraceRecordConfiguration, logger: FBControlCoreLogger) async throws -> FBXCTraceRecordOperation {
    let queue = DispatchQueue(label: "com.facebook.fbcontrolcore.xctrace")
    let traceDir = (target.auxillaryDirectory as NSString).appendingPathComponent("xctrace-" + UUID().uuidString)
    do {
      try FileManager.default.createDirectory(atPath: traceDir, withIntermediateDirectories: false, attributes: nil)
    } catch {
      throw FBControlCoreError.describe("Failed to create xctrace trace output directory: \(error)").build()
    }
    let traceFile = (traceDir as NSString).appendingPathComponent("trace.trace")

    var arguments: [String] = ["record", "--template", configuration.templateName, "--device", target.udid, "--output", traceFile, "--time-limit", "\(Int(configuration.timeLimit))s"]
    if let package = configuration.package, !package.isEmpty {
      arguments.append(contentsOf: ["--package", package])
    }
    if let targetStdin = configuration.targetStdin, !targetStdin.isEmpty {
      arguments.append(contentsOf: ["--target-stdin", targetStdin])
    }
    if let targetStdout = configuration.targetStdout, !targetStdout.isEmpty {
      arguments.append(contentsOf: ["--target-stdout", targetStdout])
    }
    if configuration.allProcesses {
      arguments.append("--all-processes")
    }
    if let processToAttach = configuration.processToAttach, !processToAttach.isEmpty {
      arguments.append(contentsOf: ["--attach", processToAttach])
    }
    if let processToLaunch = configuration.processToLaunch, !processToLaunch.isEmpty {
      if let processEnv = configuration.processEnv {
        for (key, value) in processEnv {
          arguments.append(contentsOf: ["--env", "\(key)=\(value)"])
        }
      }
      arguments.append(contentsOf: ["--launch", "--", processToLaunch])
      if let launchArgs = configuration.launchArgs {
        arguments.append(contentsOf: launchArgs)
      }
    }
    logger.log("Starting xctrace with arguments: \(FBCollectionInformation.oneLineDescription(from: arguments))")

    // Find the absolute path to xctrace
    let xctracePath = try Self.xctracePath()

    var environment: [String: String] = [:]
    if let customDeviceSetPath = target.customDeviceSetPath {
      guard let shim = configuration.shim else {
        throw FBControlCoreError.describe("Failed to locate the shim file for xctrace method swizzling").build()
      }
      environment["SIM_DEVICE_SET_PATH"] = customDeviceSetPath
      environment["DYLD_INSERT_LIBRARIES"] = shim.macOSTestShimPath
    }

    let started = try await bridgeFBFuture(
      FBProcessBuilder<AnyObject, AnyObject, AnyObject>
        .withLaunchPath(xctracePath)
        .withArguments(arguments)
        .withEnvironmentAdditions(environment)
        .withStdOut(to: logger)
        .withStdErr(to: logger)
        .withTaskLifecycleLogging(to: logger)
        .start())
    logger.log("Started xctrace \(started)")
    let typedTask = unsafeBitCast(started, to: FBSubprocess<AnyObject, AnyObject, AnyObject>.self)
    return FBXCTraceRecordOperation(task: typedTask, traceDir: URL(fileURLWithPath: traceFile), configuration: configuration, queue: queue, logger: logger)
  }

  // MARK: Public Methods

  /// Stops the xctrace recording and returns the trace directory URL on success.
  public func stop(withTimeout timeout: TimeInterval) async throws -> URL {
    let url = try await bridgeFBFuture(self.stopFuture(withTimeout: timeout))
    return url as URL
  }

  private func stopFuture(withTimeout timeout: TimeInterval) -> FBFuture<NSURL> {
    let result = FBFuture<AnyObject>.onQueue(
      queue,
      resolve: {
        self.logger.log("Terminating xctrace record \(self.task). Backoff Timeout \(timeout)")
        return self.task.sendSignal(SIGINT, backingOffToKillWithTimeout: timeout, logger: self.logger) as! FBFuture<AnyObject>
      }
    ).chainReplace(
      self.task.exitCode
        .onQueue(
          self.queue,
          fmap: { exitCode -> FBFuture<AnyObject> in
            if exitCode.isEqual(to: NSNumber(value: 0)) {
              return FBFuture<AnyObject>(result: self.traceDir as NSURL)
            } else {
              return FBControlCoreError.describe("Xctrace record exited with failure - status: \(exitCode)").failFuture()
            }
          })
    )
    return unsafeBitCast(result, to: FBFuture<NSURL>.self)
  }

  public class func xctracePath() throws -> String {
    let path = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("/usr/bin/xctrace")
    if !FileManager.default.fileExists(atPath: path) {
      throw FBControlCoreError.describe("xctrace does not exist at expected path \(path)").build()
    }
    return path
  }
}
