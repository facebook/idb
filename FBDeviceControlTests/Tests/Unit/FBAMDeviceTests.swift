/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Testing

// MARK: - File-scope state for C function pointer callbacks

private var sAMDeviceEvents: [String] = []

// MARK: - Test class

/// Pinned to the main actor: the AMDevice stubs append to `sAMDeviceEvents` from the device's
/// work and async queues, both of which are `DispatchQueue.main`, so the assertions have to read
/// it there too.
/// The session is stopped and the device disconnected before the connection is invalidated: the
/// service is started inside a pop, so the AMDevice session is not held for the caller's use of
/// the connection.
private let startServiceEvents = [
  "connect",
  "is_paired",
  "validate_pairing",
  "start_session",
  "secure_start_service",
  "service_connection_get_secure_io_context",
  "stop_session",
  "disconnect",
  "service_connection_invalidate",
]

// Serialized: the stubs append to the file-scope `sAMDeviceEvents` from the
// main queue; parallel tests would interleave their recordings.
@MainActor
@Suite(.serialized)
final class FBAMDeviceTests {

  private let device: FBAMDevice

  init() {
    device = Self.makeDevice(connectionReuseTimeout: nil, serviceReuseTimeout: nil)
  }

  // MARK: - Helpers

  private static var stubbedCalls: AMDCalls {
    var calls = FBCreateZeroedAMDCalls()

    calls.Retain = { _ in }

    calls.Release = { _ in }

    calls.Connect = { _ in
      sAMDeviceEvents.append("connect")
      return 0
    }

    calls.Disconnect = { _ in
      sAMDeviceEvents.append("disconnect")
      return 0
    }

    calls.StartSession = { _ in
      sAMDeviceEvents.append("start_session")
      return 0
    }

    calls.StopSession = { _ in
      sAMDeviceEvents.append("stop_session")
      return 0
    }

    calls.CopyValue = { _, _, name in
      guard let name else { return nil }
      return Unmanaged.passUnretained(name)
    }

    calls.IsPaired = { _ in
      sAMDeviceEvents.append("is_paired")
      return 1
    }

    calls.ValidatePairing = { _ in
      sAMDeviceEvents.append("validate_pairing")
      return 0
    }

    calls.SecureStartService = { _, _, _, serviceOut in
      sAMDeviceEvents.append("secure_start_service")
      serviceOut?.pointee = Unmanaged<AnyObject>.passRetained("A Service" as CFString)
      return 0
    }

    calls.ServiceConnectionGetSecureIOContext = { _ in
      sAMDeviceEvents.append("service_connection_get_secure_io_context")
      return nil
    }

    calls.ServiceConnectionInvalidate = { _ in
      sAMDeviceEvents.append("service_connection_invalidate")
      return 0
    }

    calls.CreateHouseArrestService = { _, _, _, connectionOut in
      sAMDeviceEvents.append("create_house_arrest_service")
      connectionOut?.pointee = Unmanaged<AnyObject>.passRetained("A HOUSE ARREST" as CFString)
      return 0
    }

    return calls
  }

  private static func makeDevice(connectionReuseTimeout: NSNumber?, serviceReuseTimeout: NSNumber?) -> FBAMDevice {
    sAMDeviceEvents.removeAll()
    #expect(sAMDeviceEvents.isEmpty)

    let device = FBAMDevice(
      allValues: ["UniqueDeviceID": "foo"],
      calls: stubbedCalls,
      connectionReuseTimeout: connectionReuseTimeout,
      serviceReuseTimeout: serviceReuseTimeout,
      work: DispatchQueue.main,
      asyncQueue: DispatchQueue.main,
      logger: FBControlCoreGlobalConfiguration.defaultLogger
    )
    device.amDeviceRef = ("A DEVICE" as CFString)
    #expect(sAMDeviceEvents.isEmpty)
    sAMDeviceEvents.removeAll()
    return device
  }

  // MARK: - Tests

  /// The context teardown (`stop_session`, `disconnect`) is enqueued on the main queue when the
  /// popped future resolves, so it can still be pending when the await resumes.
  private func waitForDeviceEvents(
    _ expected: [String],
    timeout: TimeInterval = 5,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, sAMDeviceEvents != expected {
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    if sAMDeviceEvents != expected {
      Issue.record(
        "Timed out after \(timeout)s waiting for the device events to settle, last saw \(sAMDeviceEvents)",
        sourceLocation: sourceLocation)
    }
  }

  @Test
  func connectToDeviceWithSuccess() async throws {
    let future = device.connectionContextManager.utilize(withPurpose: "test")
      .onQueue(
        DispatchQueue.main,
        pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result: NSNull())
        })

    let value = try await bridgeFBFuture(future)
    #expect(value is NSNull, "the pop block resolves with NSNull, got \(value)")

    let expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "stop_session",
      "disconnect",
    ]
    await waitForDeviceEvents(expected)

    #expect((expected) == (sAMDeviceEvents))
  }

  @Test
  func connectToDeviceWithFailure() async {
    let future = device.connectionContextManager.utilize(withPurpose: "test")
      .onQueue(
        DispatchQueue.main,
        pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
          return FBDeviceControlError.describe("A bad thing").failFuture()
        })

    do {
      _ = try await bridgeFBFuture(future)
      Issue.record("Expected the connection future to fail")
    } catch {
      #expect(error.localizedDescription.contains("A bad thing"), "the pop block's failure should surface, got \(error)")
    }

    let expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "stop_session",
      "disconnect",
    ]
    await waitForDeviceEvents(expected)

    #expect((expected) == (sAMDeviceEvents))
  }

  /// Pins the two lifetimes `startService` manages, which are not the same: the AMDevice session
  /// is released as soon as the service has started, while the service connection is invalidated
  /// only when the caller finishes with it.
  @Test
  func startService_StartsTheServiceThenInvalidatesTheConnection() async throws {
    let name = try await withFBFutureContext(device.startService("com.apple.testservice")) { connection in
      connection.name
    }
    #expect((name) == ("com.apple.testservice"))

    await waitForDeviceEvents(startServiceEvents)
    #expect((startServiceEvents) == (sAMDeviceEvents))
  }

  @Test
  func withServiceConnection_InvalidatesTheConnectionWhenTheBodyReturns() async throws {
    let name = try await device.withServiceConnection("com.apple.testservice") { $0.name }
    #expect((name) == ("com.apple.testservice"))

    await waitForDeviceEvents(startServiceEvents)
    #expect((startServiceEvents) == (sAMDeviceEvents))
  }

  /// The connection is invalidated on the way out of a throwing body, not just a returning one.
  @Test
  func withServiceConnection_InvalidatesTheConnectionWhenTheBodyThrows() async throws {
    struct BodyError: Error {}
    do {
      try await device.withServiceConnection("com.apple.testservice") { _ in throw BodyError() }
      Issue.record("Expected the body's error to propagate")
    } catch is BodyError {
      // Expected.
    }

    await waitForDeviceEvents(startServiceEvents)
    #expect((startServiceEvents) == (sAMDeviceEvents))
  }

  @Test
  func concurrentHouseArrest() async throws {
    var afcCalls = AFCCalls()
    afcCalls.ConnectionClose = { _ in
      sAMDeviceEvents.append("connection_close")
      return 0
    }

    let map = DispatchQueue(label: "com.facebook.fbdevicecontrol.amdevicetests.map")
    let device = Self.makeDevice(connectionReuseTimeout: 0.5, serviceReuseTimeout: 0.3)
    let future0: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future1: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future2: FBMutableFuture<NSNumber> = FBMutableFuture()

    // Register the three consumers from this one thread, in order: dispatching
    // the registrations onto a concurrent queue leaves their ordering to the
    // scheduler, and under loaded CI hosts one can slip past another's release
    // and reuse window, splitting the shared connection into a second connect
    // sequence and flaking the call-order assertions below.
    do {
      let inner = device.houseArrestAFCConnection(forBundleID: "com.foo.bar", afcCalls: afcCalls)
        .onQueue(
          map,
          pop: { (_: FBAFCConnection) -> FBFuture<AnyObject> in
            return FBFuture<AnyObject>(result: NSNumber(value: 0))
          })
      future0.resolve(from: inner)
    }
    do {
      let inner = device.houseArrestAFCConnection(forBundleID: "com.foo.bar", afcCalls: afcCalls)
        .onQueue(
          map,
          pop: { (_: FBAFCConnection) -> FBFuture<AnyObject> in
            return FBFuture<AnyObject>(result: NSNumber(value: 1))
          })
      future1.resolve(from: inner)
    }
    do {
      let inner = device.houseArrestAFCConnection(forBundleID: "com.foo.bar", afcCalls: afcCalls)
        .onQueue(
          map,
          pop: { (_: FBAFCConnection) -> FBFuture<AnyObject> in
            return FBFuture<AnyObject>(result: NSNumber(value: 2))
          })
      future2.resolve(from: inner)
    }

    let value = try await bridgeFBFuture(FBFuture<AnyObject>.combine([future0, future1, future2]))
    #expect(value != nil)

    var expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "create_house_arrest_service",
    ]
    await waitForDeviceEvents(expected)
    #expect((expected) == (sAMDeviceEvents))

    _ = try? await bridgeFBFuture(FBFuture<NSNull>(delay: 0.5, future: FBFuture<NSNull>.empty()))
    expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "create_house_arrest_service",
      "connection_close",
      "stop_session",
      "disconnect",
    ]
    await waitForDeviceEvents(expected)
    #expect((expected) == (sAMDeviceEvents))
  }

  @Test
  func concurrentUtilizationHasSharedConnection() async throws {
    let map = DispatchQueue(label: "com.facebook.fbdevicecontrol.amdevicetests.map")
    let future0: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future1: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future2: FBMutableFuture<NSNumber> = FBMutableFuture()

    let device = self.device

    // Register the three consumers from this one thread, in order: dispatching
    // the registrations onto a concurrent queue leaves their ordering to the
    // scheduler, and under loaded CI hosts one can slip past another's release
    // and reuse window, splitting the shared connection into a second connect
    // sequence and flaking the call-order assertions below.
    do {
      let future = device.connectionContextManager.utilize(withPurpose: "test")
        .onQueue(
          map,
          pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
            return FBFuture<AnyObject>(result: NSNumber(value: 0))
          })
      future0.resolve(from: future)
    }
    do {
      let future = device.connectionContextManager.utilize(withPurpose: "test")
        .onQueue(
          map,
          pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
            return FBFuture<AnyObject>(result: NSNumber(value: 1))
          })
      future1.resolve(from: future)
    }
    do {
      let future = device.connectionContextManager.utilize(withPurpose: "test")
        .onQueue(
          map,
          pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
            return FBFuture<AnyObject>(result: NSNumber(value: 2))
          })
      future2.resolve(from: future)
    }

    let value = try await bridgeFBFuture(FBFuture<AnyObject>.combine([future0, future1, future2])) as? [NSNumber]
    #expect((value) == ([0, 1, 2]))

    let expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "stop_session",
      "disconnect",
    ]
    await waitForDeviceEvents(expected)
    #expect((expected) == (sAMDeviceEvents))
  }
}
