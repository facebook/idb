/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBXCTraceRecordOperation)
public final class FBXCTraceRecordOperation: NSObject, FBiOSTargetOperation {

  // MARK: Properties

  @objc public let task: FBSubprocess<AnyObject, AnyObject, AnyObject>
  @objc public let queue: DispatchQueue
  @objc public let traceDir: URL
  @objc public let configuration: FBXCTraceRecordConfiguration
  @objc public let logger: FBControlCoreLogger

  // MARK: Initializers

  @objc
  public init(task: FBSubprocess<AnyObject, AnyObject, AnyObject>, traceDir: URL, configuration: FBXCTraceRecordConfiguration, queue: DispatchQueue, logger: FBControlCoreLogger) {
    self.task = task
    self.traceDir = traceDir
    self.configuration = configuration
    self.queue = queue
    self.logger = logger
    super.init()
  }

  @objc(operationWithTarget:configuration:logger:)
  public class func operation(with target: FBiOSTarget, configuration: FBXCTraceRecordConfiguration, logger: FBControlCoreLogger) -> FBFuture<FBXCTraceRecordOperation> {
    let queue = DispatchQueue(label: "com.facebook.fbcontrolcore.xctrace")
    let traceDir = (target.auxillaryDirectory as NSString).appendingPathComponent("xctrace-" + UUID().uuidString)
    do {
      try FileManager.default.createDirectory(atPath: traceDir, withIntermediateDirectories: false, attributes: nil)
    } catch {
      return FBControlCoreError.describe("Failed to create xctrace trace output directory: \(error)").failFuture() as! FBFuture<FBXCTraceRecordOperation>
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
    var xctraceError: NSError?
    guard let xctracePath = xctracePathWithError(&xctraceError) else {
      return FBControlCoreError.failFuture(with: xctraceError!) as! FBFuture<FBXCTraceRecordOperation>
    }

    var environment: [String: String] = [:]
    if let customDeviceSetPath = target.customDeviceSetPath {
      guard let shim = configuration.shim else {
        return FBControlCoreError.describe("Failed to locate the shim file for xctrace method swizzling").failFuture() as! FBFuture<FBXCTraceRecordOperation>
      }
      environment["SIM_DEVICE_SET_PATH"] = customDeviceSetPath
      environment["DYLD_INSERT_LIBRARIES"] = shim.macOSTestShimPath
    }

    let result = FBProcessBuilder<AnyObject, AnyObject, AnyObject>
      .withLaunchPath(xctracePath)
      .withArguments(arguments)
      .withEnvironmentAdditions(environment)
      .withStdOut(to: logger)
      .withStdErr(to: logger)
      .withTaskLifecycleLogging(to: logger)
      .start()
      .onQueue(target.asyncQueue, map: { task -> AnyObject in
        logger.log("Started xctrace \(task)")
        let typedTask = unsafeBitCast(task, to: FBSubprocess<AnyObject, AnyObject, AnyObject>.self)
        return FBXCTraceRecordOperation(task: typedTask, traceDir: URL(fileURLWithPath: traceFile), configuration: configuration, queue: queue, logger: logger)
      })
    return unsafeBitCast(result, to: FBFuture<FBXCTraceRecordOperation>.self)
  }

  // MARK: Public Methods

  @objc
  public func stop(withTimeout timeout: TimeInterval) -> FBFuture<NSURL> {
    let result = FBFuture<AnyObject>.onQueue(queue, resolve: {
      self.logger.log("Terminating xctrace record \(self.task). Backoff Timeout \(timeout)")
      return self.task.sendSignal(SIGINT, backingOffToKillWithTimeout: timeout, logger: self.logger) as! FBFuture<AnyObject>
    }).chainReplace(
      self.task.exitCode
        .onQueue(self.queue, fmap: { exitCode -> FBFuture<AnyObject> in
          if exitCode.isEqual(to: NSNumber(value: 0)) {
            return FBFuture<AnyObject>(result: self.traceDir as NSURL)
          } else {
            return FBControlCoreError.describe("Xctrace record exited with failure - status: \(exitCode)").failFuture()
          }
        })
    )
    return unsafeBitCast(result, to: FBFuture<NSURL>.self)
  }

  @objc(postProcess:traceDir:queue:logger:)
  public class func postProcess(_ arguments: [String]?, traceDir: URL, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<NSURL> {
    guard let arguments = arguments, !arguments.isEmpty else {
      return FBFuture<NSURL>(result: traceDir as NSURL)
    }
    let outputTraceFile = traceDir.deletingLastPathComponent().appendingPathComponent(arguments[2])
    var launchArguments: [String] = [arguments[1], traceDir.path, "-o", outputTraceFile.path]
    if arguments.count > 3 {
      launchArguments.append(contentsOf: Array(arguments[3...]))
    }

    logger?.log("Starting post processing | Launch path: \(arguments[0]) | Arguments: \(FBCollectionInformation.oneLineDescription(from: launchArguments))")
    let result = FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath(arguments[0])
      .withArguments(launchArguments)
      .withStdInConnected()
      .withStdOut(to: logger!)
      .withStdErr(to: logger!)
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: Set([NSNumber(value: 0)]))
      .onQueue(queue, map: { _ -> AnyObject in
        return outputTraceFile as NSURL
      })
    return unsafeBitCast(result, to: FBFuture<NSURL>.self)
  }

  @objc
  public class func xctracePathWithError(_ error: NSErrorPointer) -> String? {
    let path = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("/usr/bin/xctrace")
    if !FileManager.default.fileExists(atPath: path) {
      return FBControlCoreError.describe("xctrace does not exist at expected path \(path)").fail(error) as? String
    }
    return path
  }

  // MARK: FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    let result = task.exited(withCodes: Set([NSNumber(value: 0)]))
      .mapReplace(NSNull())
      .onQueue(queue, respondToCancellation: {
        return self.stop(withTimeout: DefaultXCTraceRecordStopTimeout).mapReplace(NSNull()) as! FBFuture<NSNull>
      })
    return unsafeBitCast(result, to: FBFuture<NSNull>.self)
  }
}
