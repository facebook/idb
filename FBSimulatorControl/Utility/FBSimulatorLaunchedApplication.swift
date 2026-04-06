/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBSimulatorLaunchedApplication)
public class FBSimulatorLaunchedApplication: NSObject, FBLaunchedApplication {

  // MARK: - Properties

  @objc public let configuration: FBApplicationLaunchConfiguration
  @objc public let processIdentifier: pid_t
  @objc public let applicationTerminated: FBFuture<NSNull>

  // MARK: - Private Properties

  private let attachment: FBProcessFileAttachment
  private weak var simulator: FBSimulator?

  // MARK: - FBLaunchedApplication Protocol

  @objc public var bundleID: String {
    return configuration.bundleID
  }

  @objc public var stdOut: (any FBProcessFileOutput)? {
    return attachment.stdOut
  }

  @objc public var stdErr: (any FBProcessFileOutput)? {
    return attachment.stdErr
  }

  // MARK: - Factory

  @objc
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
      }) as! FBFuture<FBSimulatorLaunchedApplication>
  }

  // MARK: - Helpers

  @objc
  public class func terminationFuture(
    forSimulator simulator: FBSimulator,
    processIdentifier: pid_t
  ) -> FBFuture<NSNull> {
    let notifierFuture =
      processTerminationFutureNotifier(forProcessIdentifier: processIdentifier)
      .mapReplace(NSNull()) as! FBFuture<NSNull>
    return
      notifierFuture
      .onQueue(
        simulator.workQueue,
        respondToCancellation: {
          return
            FBProcessTerminationStrategy
            .strategy(withProcessFetcher: FBProcessFetcher(), workQueue: simulator.workQueue, logger: simulator.logger!)
            .killProcessIdentifier(processIdentifier)
        })
  }

  // MARK: - Private Init

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
          return attachment.detach().chainReplace(future)
        }) as! FBFuture<NSNull>
    super.init()
  }

  // MARK: - Private

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

    // swiftlint:disable:next force_cast
    return unsafeBitCast(future, to: FBFuture<NSNumber>.self)
  }

  // MARK: - NSObject

  public override var description: String {
    return "Application Operation \(configuration.description) | pid \(processIdentifier) | State \(applicationTerminated)"
  }
}
