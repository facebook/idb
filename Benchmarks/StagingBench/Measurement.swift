/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import FBArtifactStaging
import FBControlCore
import Foundation
import os

/// Where the archive arrives from, as each of staging's callers hands it over.
enum BenchSource: String, Codable, CaseIterable {
  /// A path on the host, as a local install.
  case path
  /// In memory in 64 KiB frames, as a gRPC client streams it.
  case stream64K = "stream-64k"
  /// In memory in 1 MiB frames.
  case stream1M = "stream-1m"
  /// Over HTTP from a server on this host, as a URL install.
  case url
  /// From a pipe that another thread writes the file into, as `cat app.ipa | idb2 install -`.
  case pipe

  static func parse(_ value: String) throws -> BenchSource {
    guard let source = BenchSource(rawValue: value) else {
      throw ValidationError("Unknown source \(value)")
    }
    return source
  }
}

struct BenchCase: Codable, Hashable {
  let source: BenchSource
  let format: BenchFormat
  let shape: FixtureShape
  let contents: FixtureContents

  var name: String { "\(source.rawValue) \(format.rawValue) \(shape.name) \(contents.rawValue)" }
}

/// One staging of one case.
struct Measurement: Codable {
  let label: String
  let benchCase: BenchCase
  /// The archive's size on the wire.
  let archiveBytes: Int
  let wallSeconds: Double
  /// User and system time of this process and any children it waited for, such as `bsdtar`.
  let cpuSeconds: Double
  let peakRSSBytes: Int
  /// The extractors staging reported taking, in order.
  let routes: [String]
  /// How the zstd fixtures were compressed: by `zstd`, or as stored blocks when none is installed.
  let zstd: String
  let failure: String?

  /// The app's size per second, so that formats compare on what they deliver rather than on how well they compress.
  var megabytesPerSecond: Double { Double(benchCase.shape.megabytes) / wallSeconds }

  var summary: String {
    let outcome = failure.map { "FAILED \($0)" } ?? String(format: "%.0f MB/s, %.2fs CPU, %d MB peak", megabytesPerSecond, cpuSeconds, peakRSSBytes >> 20)
    return "[\(label)] \(benchCase.name): \(outcome) \(routes)"
  }

  // MARK: - Spawning

  static func spawn(binary: String, benchCase: BenchCase, archive: URL, label: String) throws -> Measurement {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = [
      "measure", "--source", benchCase.source.rawValue, "--format", benchCase.format.rawValue, "--megabytes", "\(benchCase.shape.megabytes)",
      "--files", "\(benchCase.shape.files)", "--contents", benchCase.contents.rawValue, "--archive", archive.path, "--label", label,
    ]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let line = data.split(separator: UInt8(ascii: "\n")).last else {
      throw ValidationError("\(binary) measure exited \(process.terminationStatus) for \(benchCase.name)")
    }
    return try JSONDecoder().decode(Measurement.self, from: Data(line))
  }

  // MARK: - Measuring

  static func measure(_ benchCase: BenchCase, archive: URL, label: String) async throws -> Measurement {
    let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
    let temporaryDirectory = TemporaryDirectory(logger: logger)
    let archiveBytes = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int ?? 0
    let routes = OSAllocatedUnfairLock<[String]>(initialState: [])
    let onReport: @Sendable (StagingReport) -> Void = { report in
      if case .route(let route) = report {
        routes.withLock { $0.append(route.extractor.rawValue) }
      }
    }
    let options = InstallOptions(compression: benchCase.format.declaredCompression)

    // Everything a source needs before the clock starts: frames in memory, a server listening.
    let prepared = try await PreparedSource(benchCase.source, archive: archive)
    defer { prepared.stop() }

    let usageBefore = ResourceUsage.now()
    let start = ContinuousClock.now
    var failure: String?
    do {
      try await prepared.stage(options: options, temporaryDirectory: temporaryDirectory, logger: logger, onReport: onReport)
    } catch {
      failure = "\(error)"
    }
    let wall = ContinuousClock.now - start
    let usageAfter = ResourceUsage.now()

    return Measurement(
      label: label, benchCase: benchCase, archiveBytes: archiveBytes,
      wallSeconds: Double(wall.components.seconds) + Double(wall.components.attoseconds) / 1e18,
      cpuSeconds: usageAfter.cpuSeconds - usageBefore.cpuSeconds, peakRSSBytes: usageAfter.peakRSSBytes,
      routes: routes.withLock { $0 }, zstd: Fixtures.zstdCompressor == nil ? "stored" : "zstd -3", failure: failure)
  }
}

/// A source ready to stage, with whatever it holds open until `stop`.
final class PreparedSource: Sendable {

  private let source: BenchSource
  private let archive: URL
  private let frames: [Data]
  private let server: LocalHTTPServer?

  init(_ source: BenchSource, archive: URL) async throws {
    self.source = source
    self.archive = archive
    switch source {
    case .stream64K, .stream1M:
      let contents = try Data(contentsOf: archive)
      let size = source == .stream64K ? 64 << 10 : 1 << 20
      frames = stride(from: 0, to: contents.count, by: size).map { contents.subdata(in: $0..<min($0 + size, contents.count)) }
      server = nil
    case .url:
      frames = []
      server = try await LocalHTTPServer.serving(archive)
    case .path, .pipe:
      frames = []
      server = nil
    }
  }

  func stop() {
    server?.stop()
  }

  func stage(
    options: InstallOptions, temporaryDirectory: TemporaryDirectory, logger: any ControlCoreLogger, onReport: @escaping @Sendable (StagingReport) -> Void
  ) async throws {
    switch source {
    case .path:
      try await Staging.withMaterialized(
        .localPath(archive.path), as: .application, options: options, temporaryDirectory: temporaryDirectory, logger: logger, onReport: onReport
      ) { _ in }
    case .url:
      guard let server else {
        throw ValidationError("the URL source has no server")
      }
      try await Staging.withMaterialized(
        .remoteURL(server.url), as: .application, options: options, temporaryDirectory: temporaryDirectory, logger: logger, onReport: onReport
      ) { _ in }
    case .stream64K, .stream1M:
      let frames = self.frames
      try await stream(
        AsyncThrowingStream { continuation in
          frames.forEach { continuation.yield($0) }
          continuation.finish()
        }, options: options, temporaryDirectory: temporaryDirectory, logger: logger, onReport: onReport)
    case .pipe:
      try await stream(try Self.pipeChunks(of: archive), options: options, temporaryDirectory: temporaryDirectory, logger: logger, onReport: onReport)
    }
  }

  /// Pumps `chunks` into staging as the companion and sime2e do: concurrently, through the pipe staging reads.
  private func stream(
    _ chunks: AsyncThrowingStream<Data, any Error>, options: InstallOptions, temporaryDirectory: TemporaryDirectory, logger: any ControlCoreLogger,
    onReport: @escaping @Sendable (StagingReport) -> Void
  ) async throws {
    let pipe = BytePipe()
    async let pumped: Void = {
      defer { pipe.input.finish() }
      try await PayloadPump.write(head: Data(), frames: chunks, to: pipe.input)
    }()
    do {
      try await Staging.withMaterialized(
        .stream(pipe), as: .application, options: options, temporaryDirectory: temporaryDirectory, logger: logger, onReport: onReport
      ) { _ in }
    } catch {
      try? await pumped
      throw error
    }
    try await pumped
  }

  /// The archive written into a kernel pipe by another thread, read back in 64 KiB chunks, as a shell pipeline feeds
  /// standard input. A write that fails, which happens once staging stops reading, ends the archive there.
  private static func pipeChunks(of archive: URL) throws -> AsyncThrowingStream<Data, any Error> {
    var descriptors: [Int32] = [0, 0]
    guard pipe(&descriptors) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let (readEnd, writeEnd) = (descriptors[0], descriptors[1])
    Thread {
      defer { close(writeEnd) }
      guard let input = FileHandle(forReadingAtPath: archive.path) else {
        return
      }
      while let chunk = try? input.read(upToCount: 1 << 16), !chunk.isEmpty, writeAll(chunk, to: writeEnd) {}
    }.start()
    let handle = FileHandle(fileDescriptor: readEnd, closeOnDealloc: true)
    return AsyncThrowingStream {
      let chunk = handle.readData(ofLength: 1 << 16)
      return chunk.isEmpty ? nil : chunk
    }
  }

  private static func writeAll(_ chunk: Data, to descriptor: Int32) -> Bool {
    chunk.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else {
        return true
      }
      var offset = 0
      while offset < bytes.count {
        let written = write(descriptor, base + offset, bytes.count - offset)
        if written < 0 && errno == EINTR {
          continue
        }
        guard written > 0 else {
          return false
        }
        offset += written
      }
      return true
    }
  }
}

/// This process's CPU time, including children it has waited for, and its peak resident memory.
struct ResourceUsage {
  let cpuSeconds: Double
  let peakRSSBytes: Int

  static func now() -> ResourceUsage {
    var own = rusage()
    var children = rusage()
    getrusage(RUSAGE_SELF, &own)
    getrusage(RUSAGE_CHILDREN, &children)
    func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1e6 }
    let cpu = seconds(own.ru_utime) + seconds(own.ru_stime) + seconds(children.ru_utime) + seconds(children.ru_stime)
    // Bytes on macOS.
    return ResourceUsage(cpuSeconds: cpu, peakRSSBytes: Int(own.ru_maxrss))
  }
}
