/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import SimulatorVideo
import XCTest

final class StdinReaderTests: XCTestCase {

  /// Lines are split on newlines, and a trailing unterminated line is delivered at EOF.
  func testYieldsLinesAndFlushesTrailingLineAtEOF() async {
    var fds = [Int32](repeating: 0, count: 2)
    XCTAssertEqual(pipe(&fds), 0)
    let readFD = fds[0]
    let writeFD = fds[1]

    let payload = Array("alpha\nbeta\nno-eol".utf8)
    payload.withUnsafeBytes { _ = write(writeFD, $0.baseAddress, $0.count) }
    close(writeFD) // EOF

    var lines: [String] = []
    for await line in stdinLines(fileDescriptor: readFD) {
      lines.append(line)
    }
    close(readFD)

    XCTAssertEqual(lines, ["alpha", "beta", "no-eol"])
  }

  /// The defining property versus `FileHandle.AsyncBytes`: iteration ends on task cancellation even
  /// while the pipe is still open and idle (no EOF). An uninterruptible read would hang this test.
  func testEndsOnCancellationWithOpenIdlePipe() async {
    var fds = [Int32](repeating: 0, count: 2)
    XCTAssertEqual(pipe(&fds), 0)
    let readFD = fds[0]
    let writeFD = fds[1]

    let task = Task { () -> Int in
      var count = 0
      for await _ in stdinLines(fileDescriptor: readFD) { count += 1 }
      return count
    }

    let one = Array("one\n".utf8)
    one.withUnsafeBytes { _ = write(writeFD, $0.baseAddress, $0.count) }
    // Give the reader time to deliver the line; the write end stays open so there is no EOF.
    try? await Task.sleep(nanoseconds: 100_000_000)

    task.cancel()
    _ = await task.value // must return despite the open pipe — the point of the cancellable reader

    close(writeFD)
    close(readFD)
  }
}
