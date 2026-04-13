/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation
@preconcurrency import XCTestBootstrap

private let testmanagerdSimSockTimeout: TimeInterval = 5
private let simSockEnvKey = "TESTMANAGERD_SIM_SOCK"

@objc(FBSimulatorXCTestCommands)
public final class FBSimulatorXCTestCommands: NSObject, FBXCTestExtendedCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var isRunningXcodeBuildOperation: Bool = false

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorXCTestCommands {
    return FBSimulatorXCTestCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBXCTestCommands

  @objc(runTestWithLaunchConfiguration:reporter:logger:)
  public func runTest(withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }
    // swiftlint:disable:next force_cast
    let typedReporter = reporter as! any FBXCTestReporter

    if !testLaunchConfiguration.shouldUseXcodebuild {
      return runTest(with: testLaunchConfiguration, reporter: typedReporter, logger: logger, workingDirectory: simulator.auxillaryDirectory)
    }

    if isRunningXcodeBuildOperation {
      return
        FBSimulatorError
        .describe("Cannot Start Test Manager with Configuration \(testLaunchConfiguration) as it is already running")
        .failFuture() as! FBFuture<NSNull>
    }

    return
      (unsafeBitCast(
        FBXcodeBuildOperation.terminateAbandonedXcodebuildProcesses(
          forUDID: simulator.udid,
          processFetcher: FBProcessFetcher(),
          queue: simulator.workQueue,
          logger: logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator.workQueue,
        fmap: { [self] (_: Any) -> FBFuture<AnyObject> in
          self.isRunningXcodeBuildOperation = true
          return unsafeBitCast(self._startTest(with: testLaunchConfiguration, logger: logger), to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        simulator.workQueue,
        fmap: { (task: Any) -> FBFuture<AnyObject> in
          let subprocess = task as! FBSubprocess<AnyObject, AnyObject, AnyObject>
          return unsafeBitCast(
            FBXcodeBuildOperation.confirmExit(ofXcodebuildOperation: subprocess, configuration: testLaunchConfiguration, reporter: typedReporter, target: simulator, logger: logger),
            to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        simulator.workQueue,
        chain: { [self] (future: FBFuture<AnyObject>) -> FBFuture<AnyObject> in
          self.isRunningXcodeBuildOperation = false
          return future
        })) as! FBFuture<NSNull>
  }

  @objc(transportForTestManagerService)
  public func transportForTestManagerService() -> FBFutureContext<NSNumber> {
    guard let simulator = self.simulator else {
      return
        FBSimulatorError
        .describe("Simulator is deallocated")
        .failFutureContext() as! FBFutureContext<NSNumber>
    }

    return
      (unsafeBitCast(testManagerDaemonSocketPath(), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.asyncQueue,
        fmap: { (pathObj: Any) -> FBFuture<AnyObject> in
          let testManagerSocketString = pathObj as! String
          let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
          if socketFD == -1 {
            return FBSimulatorError.describe("Unable to create a unix domain socket").failFuture()
          }
          if !FileManager.default.fileExists(atPath: testManagerSocketString) {
            close(socketFD)
            return FBSimulatorError.describe("Simulator indicated unix domain socket for testmanagerd at path \(testManagerSocketString), but no file was found at that path.").failFuture()
          }

          let testManagerSocketCStr = testManagerSocketString.utf8CString
          if testManagerSocketCStr.count - 1 >= 0x68 {
            close(socketFD)
            return FBSimulatorError.describe("Unix domain socket path for simulator testmanagerd service '\(testManagerSocketString)' is too big to fit in sockaddr_un.sun_path").failFuture()
          }

          var remote = sockaddr_un()
          remote.sun_family = sa_family_t(AF_UNIX)
          testManagerSocketCStr.withUnsafeBufferPointer { buffer in
            withUnsafeMutablePointer(to: &remote.sun_path) { sunPathPtr in
              sunPathPtr.withMemoryRebound(to: CChar.self, capacity: Int(buffer.count)) { dest in
                _ = memcpy(dest, buffer.baseAddress!, buffer.count)
              }
            }
          }
          let length = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout.size(ofValue: remote.sun_len) + strlen(testManagerSocketString))
          let connectResult = withUnsafePointer(to: &remote) { remotePtr in
            remotePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
              connect(socketFD, sockaddrPtr, length)
            }
          }
          if connectResult == -1 {
            close(socketFD)
            return FBSimulatorError.describe("Failed to connect to testmangerd socket").failFuture()
          }
          return FBFuture(result: NSNumber(value: socketFD))
        }
      )
      .onQueue(
        simulator.asyncQueue,
        contextualTeardown: { (socketNumber: Any, _: FBFutureState) -> FBFuture<NSNull> in
          close(Int32((socketNumber as! NSNumber).intValue))
          return FBFuture<NSNull>.empty()
        })) as! FBFutureContext<NSNumber>
  }

  // MARK: - FBXCTestExtendedCommands

  @objc(listTestsForBundleAtPath:timeout:withAppAtPath:)
  public func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }

    let bundleDescriptor: FBBundleDescriptor
    do {
      bundleDescriptor = try FBBundleDescriptor.bundleWithFallbackIdentifier(fromPath: bundlePath)
    } catch {
      return FBFuture(error: error as NSError)
    }

    let configuration = FBListTestConfiguration.configuration(
      withEnvironment: [:],
      workingDirectory: simulator.auxillaryDirectory,
      testBundlePath: bundlePath,
      runnerAppPath: appPath,
      waitForDebugger: false,
      timeout: timeout,
      architectures: (bundleDescriptor.binary?.architectures as? Set<String>) ?? Set())

    return FBListTestStrategy(target: unsafeBitCast(simulator, to: (any FBiOSTarget & FBProcessSpawnCommands & FBXCTestExtendedCommands).self), configuration: configuration, logger: simulator.logger!)
      .listTests()
  }

  @objc
  public func extendedTestShim() -> FBFuture<NSString> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }

    return
      (unsafeBitCast(
        FBXCTestShimConfiguration.sharedShimConfiguration(with: simulator.logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator.asyncQueue,
        map: { (shims: Any) -> AnyObject in
          let shimConfig = shims as! FBXCTestShimConfiguration
          return shimConfig.iOSSimulatorTestShimPath as NSString
        })) as! FBFuture<NSString>
  }

  @objc
  public var xctestPath: String {
    return (FBXcodeConfiguration.developerDirectory as NSString)
      .appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest")
  }

  // MARK: - Private

  private func runTest(with testLaunchConfiguration: FBTestLaunchConfiguration, reporter: any FBXCTestReporter, logger: any FBControlCoreLogger, workingDirectory: String?) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }

    if simulator.state != .booted {
      return
        FBSimulatorError
        .describe("Simulator must be booted to run tests")
        .failFuture() as! FBFuture<NSNull>
    }
    return FBManagedTestRunStrategy.runToCompletion(
      withTarget: unsafeBitCast(simulator, to: (any FBiOSTarget & FBXCTestExtendedCommands).self),
      configuration: testLaunchConfiguration,
      codesign: FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid
        ? FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: simulator.logger)
        : nil,
      workingDirectory: simulator.auxillaryDirectory,
      reporter: reporter,
      logger: logger)
  }

  private func testManagerDaemonSocketPath() -> FBFuture<NSString> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }

    return
      (FBFuture<AnyObject>.onQueue(
        simulator.asyncQueue,
        resolveUntil: { [weak self] () -> FBFuture<AnyObject> in
          guard let self, let simulator = self.simulator else {
            return FBSimulatorError.describe("Simulator is deallocated").failFuture()
          }
          var getenvError: AnyObject?
          let socketPath = simulator.device.getenv(simSockEnvKey, error: &getenvError) as? String
          if socketPath == nil || socketPath!.isEmpty {
            return
              FBSimulatorError
              .describe("Failed to get \(simSockEnvKey) from simulator environment")
              .caused(by: getenvError as? NSError)
              .failFuture()
          }
          return FBFuture(result: socketPath! as NSString)
        }
      )
      .timeout(testmanagerdSimSockTimeout, waitingFor: "\(simSockEnvKey) to become available in the simulator environment")) as! FBFuture<NSString>
  }

  private func _startTest(with configuration: FBTestLaunchConfiguration, logger: any FBControlCoreLogger) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator is deallocated").build())
    }

    let filePath: String
    do {
      filePath = try FBXcodeBuildOperation.createXCTestRunFile(at: simulator.auxillaryDirectory, fromConfiguration: configuration)
    } catch {
      return FBFuture(error: error as NSError)
    }

    let xcodeBuildPath: String
    do {
      xcodeBuildPath = try FBXcodeBuildOperation.xcodeBuildPath()
    } catch {
      return FBFuture(error: error as NSError)
    }

    return
      (unsafeBitCast(
        FBXCTestShimConfiguration.sharedShimConfiguration(with: simulator.logger),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        simulator.asyncQueue,
        fmap: { (shims: Any) -> FBFuture<AnyObject> in
          let shimConfig = shims as! FBXCTestShimConfiguration
          return unsafeBitCast(
            FBXcodeBuildOperation.operation(
              withUDID: simulator.udid,
              configuration: configuration,
              xcodeBuildPath: xcodeBuildPath,
              testRunFilePath: filePath,
              simDeviceSet: simulator.customDeviceSetPath,
              macOSTestShimPath: shimConfig.macOSTestShimPath,
              queue: simulator.workQueue,
              logger: logger.withName("xcodebuild")),
            to: FBFuture<AnyObject>.self)
        })) as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
  }
}
