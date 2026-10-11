/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing
import os

/// A download from a server faster than the extraction reading it: how much memory the process holds while the
/// download is ahead of what has been read.
@Suite
struct DownloadBackpressureTests {

  /// Reads `source` 64 KiB at a time, pausing between reads, as an extractor slower than the link does.
  // SAFETY: its one piece of state, `consumed`, is only touched under its own lock.
  // patternlint-disable-next-line unchecked-sendable
  final class ThrottledReader: @unchecked Sendable {
    private let consumed = OSAllocatedUnfairLock(initialState: 0)

    var bytesRead: Int { consumed.withLock { $0 } }

    func read(_ source: any ByteSource, pause: TimeInterval) throws {
      var buffer = [UInt8](repeating: 0, count: 64 << 10)
      while case let count = try buffer.withUnsafeMutableBytes({ try source.read(into: $0) }), count > 0 {
        consumed.withLock { $0 += count }
        Thread.sleep(forTimeInterval: pause)
      }
    }
  }

  /// The process's physical footprint, which counts what it holds in memory and not the file cache.
  static func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
  }

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  /// Writes the body a megabyte at a time, so writing it does not itself raise the footprint being measured.
  private func writeBody(size: Int) throws -> URL {
    let body = root.appendingPathComponent("body")
    FileManager.default.createFile(atPath: body.path, contents: nil)
    let handle = try FileHandle(forWritingTo: body)
    let chunk = Data(repeating: 0x42, count: 1 << 20)
    for _ in 0..<(size >> 20) {
      try handle.write(contentsOf: chunk)
    }
    try handle.close()
    return body
  }

  /// How far the footprint rose above where it started, at most, while a body of `size` bytes downloaded into a reader
  /// slower than the link.
  private func peakFootprintGrowth(size: Int) async throws -> Int {
    let server = try await LocalHTTPServer.serving(try writeBody(size: size))
    defer { server.stop() }
    let start = Self.footprint()
    let peak = OSAllocatedUnfairLock(initialState: start)
    let sampling = Task.detached {
      while !Task.isCancelled {
        let now = Self.footprint()
        peak.withLock { $0 = max($0, now) }
        try? await Task.sleep(for: .milliseconds(20))
      }
    }
    defer { sampling.cancel() }

    let reader = ThrottledReader()
    // A host this busy can leave the server unscheduled for longer than the default minute without data.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 600
    let download = DataDownloadInput.dataDownload(withURL: server.url, configuration: configuration, logger: logger)
    try await download.pipe.reading { source in
      let source = HandedOver(source)
      try await offCooperativePool { try reader.read(source.value, pause: 0.0005) }.get()
    }
    try await download.completed()
    #expect(reader.bytesRead == size)
    return peak.withLock { $0 } - start
  }

  /// BUG: nothing holds the download back from running ahead of the reader, and everything it is ahead by is held in
  /// memory, so the footprint rises by most of the body -- flipped in the following commit. The footprint is the whole
  /// process's, and other suites share it, so the body is large enough to stand well clear of what they add: a rise of
  /// three quarters of it is the line either way.
  @Test
  func aDownloadAheadOfItsReaderIsHeldInMemory() async throws {
    let size = 1 << 30
    let growth = try await peakFootprintGrowth(size: size)
    #expect(growth > size / 4 * 3, "the footprint rose by at most \(growth >> 20) MB for a \(size >> 20) MB download")
  }
}
