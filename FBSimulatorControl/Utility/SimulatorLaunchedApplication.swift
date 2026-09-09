/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public final class FBSimulatorLaunchedApplication: FBLaunchedApplication, CustomStringConvertible {

  public let configuration: FBApplicationLaunchConfiguration
  public let processIdentifier: pid_t
  private let applicationTerminated: FBFuture<NSNull>

  // MARK: - Private Properties

  private let attachment: FBProcessFileAttachment
  private weak var simulator: FBSimulator?

  // MARK: - FBLaunchedApplication Protocol

  public var bundleID: String {
    configuration.bundleID
  }

  public func waitForTermination() async throws {
    try await bridgeFBFutureVoid(applicationTerminated)
  }

  public func terminate() async throws {
    try await bridgeFBFutureVoid(applicationTerminated.cancel())
  }

  public var stdOut: (any FBProcessFileOutput)? {
    attachment.stdOut
  }

  public var stdErr: (any FBProcessFileOutput)? {
    attachment.stdErr
  }

  // MARK: - Factory

  public class func application(
    withSimulator simulator: FBSimulator,
    configuration: FBApplicationLaunchConfiguration,
    attachment: FBProcessFileAttachment,
    launchFuture: FBFuture<NSNumber>
  ) -> FBFuture<FBSimulatorLaunchedApplication> {
    return launchFuture.onQueue(
      simulator.workQueue,
      map: { processIdentifierNumber -> FBSimulatorLaunchedApplication in
        let processIdentifier = processIdentifierNumber.int32Value
        let terminationFuture = Self.terminationFuture(
          forSimulator: simulator,
          processIdentifier: processIdentifier
        )
        return FBSimulatorLaunchedApplication(
          simulator: simulator,
          configuration: configuration,
          attachment: attachment,
          processIdentifier: processIdentifier,
          terminationFuture: terminationFuture
        )
      }
    ).retyped(FBFuture<FBSimulatorLaunchedApplication>.self)
  }

  public class func terminationFuture(
    forSimulator simulator: FBSimulator,
    processIdentifier: pid_t
  ) -> FBFuture<NSNull> {
    let notifierFuture =
      processTerminationFutureNotifier(forProcessIdentifier: processIdentifier)
      .mapReplace(NSNull()).retyped(FBFuture<NSNull>.self)
    return
      notifierFuture
      .onQueue(
        simulator.workQueue,
        respondToCancellation: {
          FBProcessTerminationStrategy
            .strategy(withProcessFetcher: FBProcessFetcher(), workQueue: simulator.workQueue, logger: simulator.logger)
            .killProcessIdentifier(processIdentifier)
        })
  }

  private init(
    simulator: FBSimulator,
    configuration: FBApplicationLaunchConfiguration,
    attachment: FBProcessFileAttachment,
    processIdentifier: pid_t,
    terminationFuture: FBFuture<NSNull>
  ) {
    self.simulator = simulator
    self.configuration = configuration
    self.attachment = attachment
    self.processIdentifier = processIdentifier
    self.applicationTerminated =
      terminationFuture.onQueue(
        simulator.workQueue,
        chain: { future in
          attachment.detach().chainReplace(future)
        }
      ).retyped(FBFuture<NSNull>.self)
  }

  private class func processTerminationFutureNotifier(
    forProcessIdentifier processIdentifier: pid_t
  ) -> FBFuture<NSNumber> {
    let queue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.application_termination_notifier")
    let source = DispatchSource.makeProcessSource(
      identifier: processIdentifier,
      eventMask: .exit,
      queue: queue
    )

    let future = FBMutableFuture<NSNumber>()
    _ = future.onQueue(
      queue,
      respondToCancellation: {
        source.cancel()
        return FBFuture<NSNull>.empty()
      })
    source.setEventHandler {
      future.resolve(withResult: NSNumber(value: processIdentifier))
      source.cancel()
    }
    source.resume()

    return unsafeBitCast(future, to: FBFuture<NSNumber>.self)
  }

  public var description: String {
    "Application Operation \(configuration.description) | pid \(processIdentifier) | State \(applicationTerminated)"
  }
}
