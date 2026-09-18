/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class AccessibilitySocketTests: XCTestCase {
  var socketPath = ""
  var finished: XCTestExpectation?

  override func setUp() {
    super.setUp()
    FBAXBridgeSetRuntimeForTesting(FBAXFakeRuntime())
  }

  override func tearDown() {
    if finished != nil {
      finishServer()
    }
    FBAXBridgeSetRuntimeForTesting(nil)
    super.tearDown()
  }

  func startServerExclusive(exclusive: Bool, idleTimeoutSeconds: Int = 10) {
    socketPath = "/tmp/sfb-" + UUID().uuidString
    let finished = expectation(description: "server exits")
    self.finished = finished
    let path = socketPath
    DispatchQueue.global().async {
      let result = FBAXBridgeServe(path, ["--idle-timeout", String(idleTimeoutSeconds), "--exit-on-disconnect", exclusive ? "1" : "0"])
      XCTAssertEqual(result, 0)
      finished.fulfill()
    }
  }

  func finishServer() {
    if let finished {
      wait(for: [finished], timeout: 15)
    } else {
      XCTFail("server was not started")
    }
    finished = nil
    XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
  }

  func connectClient() -> Int32 {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { path in
      path.withMemoryRebound(to: CChar.self, capacity: capacity) { bytes in
        socketPath.withCString { source in
          _ = strlcpy(bytes, source, capacity)
        }
      }
    }
    let deadline = Date(timeIntervalSinceNow: 5)
    repeat {
      let fd = socket(AF_UNIX, SOCK_STREAM, 0)
      if fd < 0 {
        XCTFail("socket failed")
        return -1
      }
      let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      if connected == 0 {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
      }
      close(fd)
      usleep(1000)
    } while deadline.timeIntervalSinceNow > 0
    XCTFail("server did not accept a client")
    return -1
  }

  func header(forLength length: UInt32) -> Data {
    Data([
      UInt8(truncatingIfNeeded: length >> 24), UInt8(truncatingIfNeeded: length >> 16),
      UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length),
    ])
  }

  func frame(payload: String) -> Data {
    let data = Data(payload.utf8)
    var frame = header(forLength: UInt32(data.count))
    frame.append(data)
    return frame
  }

  func sendData(data: Data, to fd: Int32) {
    data.withUnsafeBytes { buffer in
      guard let bytes = buffer.baseAddress else { return }
      var offset = 0
      while offset < data.count {
        let count = send(fd, bytes.advanced(by: offset), data.count - offset, MSG_NOSIGNAL)
        XCTAssertGreaterThan(count, 0)
        if count <= 0 { return }
        offset += count
      }
    }
  }

  func readBytes(length: Int, from fd: Int32) -> Data? {
    var data = Data(count: length)
    let complete = data.withUnsafeMutableBytes { buffer in
      guard let bytes = buffer.baseAddress else { return length == 0 }
      var offset = 0
      while offset < length {
        let count = recv(fd, bytes.advanced(by: offset), length - offset, 0)
        if count <= 0 {
          XCTFail("response ended before \(length) bytes")
          return false
        }
        offset += count
      }
      return true
    }
    return complete ? data : nil
  }

  func readResponse(fd: Int32) -> NSDictionary? {
    guard let header = readBytes(length: 4, from: fd) else { return nil }
    let length = (UInt32(header[0]) << 24) | (UInt32(header[1]) << 16) | (UInt32(header[2]) << 8) | UInt32(header[3])
    if length == 0 || length > 16 * 1024 * 1024 {
      XCTFail("invalid response length \(length)")
      return nil
    }
    guard let data = readBytes(length: Int(length), from: fd) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
  }

  func assertEOF(fd: Int32) {
    var byte: UInt8 = 0
    XCTAssertEqual(recv(fd, &byte, 1, 0), 0)
  }

  func testFragmentedFramesAndShutdownResponseOnOneConnection() {
    startServerExclusive(exclusive: true)
    let client = connectClient()
    let payloads = ["not json", "{\"verb\":\"shutdown\"}"]
    for payload in payloads {
      let frame = frame(payload: payload)
      for index in 0..<frame.count {
        sendData(data: frame.subdata(in: index..<(index + 1)), to: client)
        usleep(1000)
      }
      let response = readResponse(fd: client)
      if payload == "not json" {
        XCTAssertEqual(
          response,
          ["ok": false, "error": "malformed request frame", "error_kind": "bad_request"]
        )
      } else {
        XCTAssertEqual(response, ["ok": true, "shutdown": true])
      }
    }
    assertEOF(fd: client)
    close(client)
    finishServer()
  }

  func testInvalidFrameLengthsCloseTheConnection() {
    for length: UInt32 in [0, 16 * 1024 * 1024 + 1] {
      startServerExclusive(exclusive: true)
      let client = connectClient()
      sendData(data: header(forLength: length), to: client)
      assertEOF(fd: client)
      close(client)
      finishServer()
    }
  }

  func testTruncatedHeaderAndPayloadCloseTheConnection() {
    let frame = frame(payload: "{\"verb\":\"shutdown\"}")
    for length in [1, 6] {
      startServerExclusive(exclusive: true)
      let client = connectClient()
      sendData(data: frame.subdata(in: 0..<length), to: client)
      shutdown(client, SHUT_WR)
      assertEOF(fd: client)
      close(client)
      finishServer()
    }
  }

  func testSharedServerAcceptsAnotherClientAfterDisconnect() {
    startServerExclusive(exclusive: false)
    var client = connectClient()
    close(client)
    client = connectClient()
    sendData(data: frame(payload: "{\"verb\":\"shutdown\"}"), to: client)
    XCTAssertEqual(readResponse(fd: client), ["ok": true, "shutdown": true])
    assertEOF(fd: client)
    close(client)
    finishServer()
  }

  func testExclusiveServerExitsAfterDisconnect() {
    startServerExclusive(exclusive: true)
    close(connectClient())
    finishServer()
  }

  func testIdleClientTimesOutAndCloses() {
    startServerExclusive(exclusive: true, idleTimeoutSeconds: 3)
    let client = connectClient()
    sendData(data: header(forLength: 10), to: client)
    assertEOF(fd: client)
    close(client)
    finishServer()
  }

  func testIdleListenerExitsAndRemovesItsSocket() {
    startServerExclusive(exclusive: false, idleTimeoutSeconds: 1)
    finishServer()
  }

  func testOverlongSocketPathIsRejected() {
    let path = "/tmp/".padding(toLength: 200, withPad: "x", startingAt: 0)
    XCTAssertEqual(FBAXBridgeServe(path, []), 1)
  }

  func testRuntimeCallbacksStayOnTheCallingThread() {
    socketPath = "/tmp/sfb-" + UUID().uuidString
    finished = expectation(description: "client receives shutdown response")
    DispatchQueue.global().async {
      let client = self.connectClient()
      self.sendData(data: self.frame(payload: "probe"), to: client)
      XCTAssertEqual(self.readResponse(fd: client), ["ok": true])
      self.assertEOF(fd: client)
      close(client)
      self.finished?.fulfill()
    }
    let callingThread = Thread.current
    var preparations = 0
    var requests = 0
    let result = FBAXBridgeServer.serve(socketPath: socketPath, idleTimeoutSeconds: 10, exitOnDisconnect: true) {
      XCTAssertEqual(Thread.current, callingThread)
      preparations += 1
    } handleRequest: { request in
      XCTAssertEqual(Thread.current, callingThread)
      XCTAssertEqual(preparations, 1)
      XCTAssertEqual(request, "probe".data(using: .utf8))
      requests += 1
      return FBAXBridgeSocketResponse(data: Data("{\"ok\":true}".utf8), shutdown: true)
    }
    XCTAssertEqual(result, 0)
    XCTAssertEqual(preparations, 1)
    XCTAssertEqual(requests, 1)
    finishServer()
  }
}
