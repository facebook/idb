/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import FBControlCore
@testable import FBDeviceControl
import XCTest

final class FBDeviceVideoTests: XCTestCase {
  private final class AuthorizationStub {
    var status: AVAuthorizationStatus
    let statusAfterRequest: AVAuthorizationStatus?
    let granted: Bool
    var requestCount = 0

    init(
      status: AVAuthorizationStatus,
      statusAfterRequest: AVAuthorizationStatus? = nil,
      granted: Bool = false
    ) {
      self.status = status
      self.statusAfterRequest = statusAfterRequest
      self.granted = granted
    }

    func authorizationStatus() -> AVAuthorizationStatus {
      status
    }

    func requestAccess() async -> Bool {
      requestCount += 1
      if let statusAfterRequest {
        status = statusAfterRequest
      }
      return granted
    }
  }

  private enum UnexpectedCaptureError: Error {
    case captureDeviceLookup
  }

  private func logger(_ logger: CapturingLogger, contains substring: String) -> Bool {
    for case let message as String in logger.messages {
      if message.contains(substring) {
        return true
      }
    }
    return false
  }

  private func runAuthorization(
    _ authorization: AuthorizationStub,
    logger: CapturingLogger
  ) async throws {
    try await FBDeviceVideo.ensureVideoCaptureAuthorization(
      logger: logger,
      authorizationStatus: {
        authorization.authorizationStatus()
      },
      requestAccess: {
        await authorization.requestAccess()
      }
    )
  }

  private func authorizationError(
    _ authorization: AuthorizationStub,
    logger: CapturingLogger
  ) async -> NSError? {
    do {
      try await runAuthorization(authorization, logger: logger)
      XCTFail("Expected camera authorization to fail")
      return nil
    } catch {
      return error as NSError
    }
  }

  func testAuthorizedStatusSucceedsWithoutRequest() async throws {
    let authorization = AuthorizationStub(status: .authorized)
    let logger = CapturingLogger()

    try await runAuthorization(authorization, logger: logger)

    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status: authorized"))
  }

  func testDeniedStatusFailsWithoutRequest() async {
    let authorization = AuthorizationStub(status: .denied)
    let logger = CapturingLogger()

    let error = await authorizationError(authorization, logger: logger)

    XCTAssertEqual(error?.domain, FBDeviceControlErrorDomain)
    XCTAssertTrue(error?.localizedDescription.contains("Camera authorization is denied") == true)
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status: denied"))
  }

  func testRestrictedStatusFailsWithoutRequest() async {
    let authorization = AuthorizationStub(status: .restricted)
    let logger = CapturingLogger()

    let error = await authorizationError(authorization, logger: logger)

    XCTAssertEqual(error?.domain, FBDeviceControlErrorDomain)
    XCTAssertTrue(error?.localizedDescription.contains("Camera authorization is restricted") == true)
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status: restricted"))
  }

  func testNotDeterminedRequestsAccessAndSucceedsWhenAuthorized() async throws {
    let authorization = AuthorizationStub(
      status: .notDetermined,
      statusAfterRequest: .authorized,
      granted: true
    )
    let logger = CapturingLogger()

    try await runAuthorization(authorization, logger: logger)

    XCTAssertEqual(authorization.requestCount, 1)
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status: notDetermined"))
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status after request: authorized (granted=YES)"))
  }

  func testNotDeterminedRequestsAccessAndFailsWhenDenied() async {
    let authorization = AuthorizationStub(
      status: .notDetermined,
      statusAfterRequest: .denied,
      granted: false
    )
    let logger = CapturingLogger()

    let error = await authorizationError(authorization, logger: logger)

    XCTAssertEqual(error?.domain, FBDeviceControlErrorDomain)
    XCTAssertTrue(error?.localizedDescription.contains("Camera authorization is denied") == true)
    XCTAssertEqual(authorization.requestCount, 1)
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status after request: denied (granted=NO)"))
  }

  func testUnknownStatusFailsWithoutRequest() async throws {
    let unknown = try XCTUnwrap(AVAuthorizationStatus(rawValue: Int.max))
    let authorization = AuthorizationStub(status: unknown)
    let logger = CapturingLogger()

    let error = await authorizationError(authorization, logger: logger)

    XCTAssertEqual(error?.domain, FBDeviceControlErrorDomain)
    XCTAssertTrue(error?.localizedDescription.contains("unknown") == true)
    XCTAssertEqual(authorization.requestCount, 0)
    XCTAssertTrue(self.logger(logger, contains: "Camera authorization status: unknown"))
  }

  func testDeniedAuthorizationStopsBeforeScreenCaptureAndDeviceDiscovery() async {
    let authorization = AuthorizationStub(status: .denied)
    let logger = CapturingLogger()
    var allowScreenCaptureCount = 0
    var findCaptureDeviceCount = 0

    do {
      _ = try await FBDeviceVideo.captureSessionAsync(
        logger: logger,
        authorizationStatus: {
          authorization.authorizationStatus()
        },
        requestAccess: {
          await authorization.requestAccess()
        },
        allowAccessToScreenCaptureDevices: {
          allowScreenCaptureCount += 1
        },
        findCaptureDevice: {
          findCaptureDeviceCount += 1
          throw UnexpectedCaptureError.captureDeviceLookup
        }
      )
      XCTFail("Expected denied camera authorization to stop capture setup")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, FBDeviceControlErrorDomain)
    }

    XCTAssertEqual(allowScreenCaptureCount, 0)
    XCTAssertEqual(findCaptureDeviceCount, 0)
  }
}
