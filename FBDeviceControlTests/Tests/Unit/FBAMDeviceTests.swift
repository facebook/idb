// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import FBDeviceControl
import XCTest

// MARK: - File-scope state for C function pointer callbacks

private var sAMDeviceEvents: [String] = []

// MARK: - Test class

final class FBAMDeviceTests: XCTestCase {

  private var _device: FBAMDevice?

  override func tearDown() {
    _device = nil
  }

  // MARK: - Helpers

  private var stubbedCalls: AMDCalls {
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
      guard let name = name else { return nil }
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

  private func makeDevice(connectionReuseTimeout: NSNumber?, serviceReuseTimeout: NSNumber?) -> FBAMDevice {
    sAMDeviceEvents.removeAll()
    XCTAssertEqual(sAMDeviceEvents, [])

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
    XCTAssertEqual(sAMDeviceEvents, [])
    sAMDeviceEvents.removeAll()
    return device
  }

  private var device: FBAMDevice {
    if let existing = _device {
      return existing
    }
    let created = makeDevice(connectionReuseTimeout: nil, serviceReuseTimeout: nil)
    _device = created
    return created
  }

  // MARK: - Tests

  func testConnectToDeviceWithSuccess() throws {
    let future = device.connectionContextManager.utilize(withPurpose: "test")
      .onQueue(DispatchQueue.main, pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
        return FBFuture<AnyObject>(result: NSNull())
      })

    let value = try future.await()
    XCTAssertNotNil(value)

    let actual = sAMDeviceEvents
    let expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "stop_session",
      "disconnect",
    ]

    XCTAssertEqual(expected, actual)
  }

  func testConnectToDeviceWithFailure() {
    let future = device.connectionContextManager.utilize(withPurpose: "test")
      .onQueue(DispatchQueue.main, pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
        return FBDeviceControlError.describe("A bad thing").failFuture()
      })

    XCTAssertThrowsError(try future.await())

    let actual = sAMDeviceEvents
    let expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "stop_session",
      "disconnect",
    ]

    XCTAssertEqual(expected, actual)
  }

  func testConcurrentHouseArrest() throws {
    var afcCalls = AFCCalls()
    afcCalls.ConnectionClose = { _ in
      sAMDeviceEvents.append("connection_close")
      return 0
    }

    let schedule = DispatchQueue(label: "com.facebook.fbdevicecontrol.amdevicetests.schedule", attributes: .concurrent)
    let map = DispatchQueue(label: "com.facebook.fbdevicecontrol.amdevicetests.map")
    let device = makeDevice(connectionReuseTimeout: 0.5, serviceReuseTimeout: 0.3)
    let future0: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future1: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future2: FBMutableFuture<NSNumber> = FBMutableFuture()

    schedule.async {
      let inner = device.houseArrestAFCConnection(forBundleID: "com.foo.bar", afcCalls: afcCalls)
        .onQueue(map, pop: { (_: FBAFCConnection) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result:NSNumber(value: 0))
        })
      future0.resolve(from:inner)
    }
    schedule.async {
      let inner = device.houseArrestAFCConnection(forBundleID: "com.foo.bar", afcCalls: afcCalls)
        .onQueue(map, pop: { (_: FBAFCConnection) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result:NSNumber(value: 1))
        })
      future1.resolve(from:inner)
    }
    schedule.async {
      let inner = device.houseArrestAFCConnection(forBundleID: "com.foo.bar", afcCalls: afcCalls)
        .onQueue(map, pop: { (_: FBAFCConnection) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result:NSNumber(value: 2))
        })
      future2.resolve(from:inner)
    }

    let value = try FBFutureFromArray([future0, future1, future2]).await()
    XCTAssertNotNil(value)

    var actual = sAMDeviceEvents
    var expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "create_house_arrest_service",
    ]
    XCTAssertEqual(expected, actual)

    try? FBFuture<NSNull>(delay: 0.5, future: FBFuture<NSNull>.empty()).await()
    actual = sAMDeviceEvents
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
    XCTAssertEqual(expected, actual)
  }

  func testConcurrentUtilizationHasSharedConnection() throws {
    let schedule = DispatchQueue(label: "com.facebook.fbdevicecontrol.amdevicetests.schedule", attributes: .concurrent)
    let map = DispatchQueue(label: "com.facebook.fbdevicecontrol.amdevicetests.map")
    let future0: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future1: FBMutableFuture<NSNumber> = FBMutableFuture()
    let future2: FBMutableFuture<NSNumber> = FBMutableFuture()

    let device = self.device

    schedule.async {
      let future = device.connectionContextManager.utilize(withPurpose: "test")
        .onQueue(map, pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result:NSNumber(value: 0))
        })
      future0.resolve(from:future)
    }
    schedule.async {
      let future = device.connectionContextManager.utilize(withPurpose: "test")
        .onQueue(map, pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result:NSNumber(value: 1))
        })
      future1.resolve(from:future)
    }
    schedule.async {
      let future = device.connectionContextManager.utilize(withPurpose: "test")
        .onQueue(map, pop: { (_: FBAMDevice) -> FBFuture<AnyObject> in
          return FBFuture<AnyObject>(result:NSNumber(value: 2))
        })
      future2.resolve(from:future)
    }

    let value = try FBFutureFromArray([future0, future1, future2]).await() as? [NSNumber]
    XCTAssertEqual(value, [0, 1, 2])

    let actual = sAMDeviceEvents
    let expected = [
      "connect",
      "is_paired",
      "validate_pairing",
      "start_session",
      "stop_session",
      "disconnect",
    ]
    XCTAssertEqual(expected, actual)
  }
}
