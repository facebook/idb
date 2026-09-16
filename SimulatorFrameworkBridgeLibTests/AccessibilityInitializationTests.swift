/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class AccessibilityInitializationTests: XCTestCase {
  private let request: [String: Any] = ["verb": "settings-get", "setting": "reduce-motion"]

  override func setUp() {
    super.setUp()
    FBAXBridgeSetRuntimeForTesting(nil)
  }

  func testSuccessfulPreparationAndRequest() {
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.success, true, request) as NSDictionary,
      [
        "preparationException": NSNull(), "calls": 2,
        "response": ["ok": true, "enabled": true],
      ] as NSDictionary)
  }

  func testInitializationFailurePreservesTheSetupMessage() {
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.failureWithMessage, true, request) as NSDictionary,
      [
        "preparationException": NSNull(), "calls": 2,
        "response": ["ok": false, "error": "missing test framework", "error_kind": "reader_unavailable"],
      ] as NSDictionary)
  }

  func testInitializationFailureWithoutDetailsUsesTheFallback() {
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.failureWithoutMessage, true, request) as NSDictionary,
      [
        "preparationException": NSNull(), "calls": 2,
        "response": ["ok": false, "error": "accessibility setup failed", "error_kind": "reader_unavailable"],
      ] as NSDictionary)
  }

  func testInitializationExceptionWithReason() {
    // BUG: preparation lets an Objective-C initialization exception escape.
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.exceptionWithReason, true, request) as NSDictionary,
      [
        "preparationException": "initialization failed", "calls": 2,
        "response": ["ok": false, "error": "the reader raised while answering: initialization failed"],
      ] as NSDictionary)
  }

  func testInitializationExceptionWithoutReason() {
    // BUG: preparation lets an Objective-C initialization exception escape.
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.exceptionWithoutReason, true, request) as NSDictionary,
      [
        "preparationException": "NSInternalInconsistencyException", "calls": 2,
        "response": ["ok": false, "error": "the reader raised while answering: NSInternalInconsistencyException"],
      ] as NSDictionary)
  }

  func testShutdownDoesNotInitializeTheRuntime() {
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.exceptionWithReason, false, ["verb": "shutdown"]) as NSDictionary,
      [
        "preparationException": NSNull(), "calls": 0,
        "response": ["ok": true, "shutdown": true],
      ] as NSDictionary)
  }

  func testInvalidPidDoesNotInitializeTheRuntime() {
    XCTAssertEqual(
      FBAXRuntimeInitializationProbe(.exceptionWithReason, false, ["verb": "describe", "pid": 0]) as NSDictionary,
      [
        "preparationException": NSNull(), "calls": 0,
        "response": ["ok": false, "error": "pid 0 names no application", "error_kind": "application_unavailable", "pid": 0],
      ] as NSDictionary)
  }
}
