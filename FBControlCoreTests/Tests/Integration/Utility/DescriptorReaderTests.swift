/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

private final class RecordingConsumer: DataConsumer, @unchecked Sendable {
  private let lock = NSLock()
  private var received = Data()
  private var endOfFileCount = 0
  let firstData = AsyncEvent<Void>()
  let endOfFile = AsyncEvent<Void>()

  var data: Data { lock.withLock { received } }
  var endOfFiles: Int { lock.withLock { endOfFileCount } }

  func consumeData(_ data: Data) {
    lock.withLock { received.append(data) }
    firstData.happen(())
  }

  func consumeEndOfFile() {
    lock.withLock { endOfFileCount += 1 }
    endOfFile.happen(())
  }
}

/// A reader whose channel never relinquishes its descriptor hangs rather than failing, so each test
/// is capped.
@Suite(.timeLimit(.minutes(1)))
struct DescriptorReaderTests {

  @Test
  func readsToEndOfFile() async {
    let pipe = Pipe()
    let consumer = RecordingConsumer()
    let reader = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer)

    pipe.fileHandleForWriting.write(Data("Foo Bar Baz".utf8))
    pipe.fileHandleForWriting.closeFile()

    #expect(await reader.finished() == .endOfFile)
    #expect(consumer.data == Data("Foo Bar Baz".utf8))
    #expect(consumer.endOfFiles == 1)
  }

  @Test
  func stoppingDeliversEndOfFileWhileTheWriterIsStillOpen() async {
    let pipe = Pipe()
    let consumer = RecordingConsumer()
    let reader = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer)
    pipe.fileHandleForWriting.write(Data("Foo Bar Baz".utf8))

    reader.stop()

    #expect(await reader.finished() == .stopped)
    #expect(consumer.endOfFiles == 1)
    pipe.fileHandleForWriting.closeFile()
  }

  @Test
  func stoppingTwiceAndWaitingTwiceGiveTheSameOutcome() async throws {
    let descriptor = open("/dev/urandom", O_RDONLY)
    try #require(descriptor >= 0)
    let consumer = RecordingConsumer()
    let reader = DescriptorReader(fileDescriptor: descriptor, closeOnEndOfFile: true, consumer: consumer)

    reader.stop()
    reader.stop()

    #expect(await reader.finished() == .stopped)
    #expect(await reader.finished() == .stopped)
    #expect(consumer.endOfFiles == 1)
  }

  @Test
  func concurrentWaitersAllSeeTheOutcome() async {
    let pipe = Pipe()
    let reader = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: RecordingConsumer())
    async let first = reader.finished()
    async let second = reader.finished()

    pipe.fileHandleForWriting.closeFile()

    #expect(await [first, second] == [.endOfFile, .endOfFile])
  }

  @Test
  func cancellingTheWaitStopsReading() async {
    let pipe = Pipe()
    let consumer = RecordingConsumer()
    let reader = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer)
    let wait = Task { await reader.finished() }

    wait.cancel()

    #expect(await wait.value == .stopped)
    #expect(consumer.endOfFiles == 1)
    pipe.fileHandleForWriting.closeFile()
  }

  @Test
  func waitingWithinATimeoutStopsReadingWhenItElapses() async {
    let pipe = Pipe()
    let reader = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: RecordingConsumer())

    #expect(await reader.finished(within: 0.1) == .stopped)
    pipe.fileHandleForWriting.closeFile()
  }

  @Test
  func waitingWithinATimeoutReturnsEndOfFileWhenItArrivesFirst() async {
    let pipe = Pipe()
    let reader = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: RecordingConsumer())

    pipe.fileHandleForWriting.closeFile()

    #expect(await reader.finished(within: 30) == .endOfFile)
  }

  @Test
  func closesAnOwnedDescriptorOnceRelinquished() async {
    var descriptors: [Int32] = [0, 0]
    #expect(Darwin.pipe(&descriptors) == 0)
    let reader = DescriptorReader(fileDescriptor: descriptors[0], closeOnEndOfFile: true, consumer: RecordingConsumer())

    close(descriptors[1])

    #expect(await reader.finished() == .endOfFile)
    #expect(fcntl(descriptors[0], F_GETFD) == -1)
  }

  @Test
  func keepsReadingWhenDropped() async throws {
    let pipe = Pipe()
    let consumer = RecordingConsumer()
    _ = DescriptorReader(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, closeOnEndOfFile: false, consumer: consumer)

    pipe.fileHandleForWriting.write(Data("Foo".utf8))
    pipe.fileHandleForWriting.closeFile()

    try await consumer.endOfFile.wait(timeout: 30, waitingFor: "end-of-file from a dropped reader")
    #expect(consumer.data == Data("Foo".utf8))
  }

  @Test
  func leavesAnUnownedSocketNonBlockingAfterTeardown() async throws {
    var descriptors: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    let localSocket = descriptors[0]
    let remoteSocket = descriptors[1]
    defer {
      close(localSocket)
      close(remoteSocket)
    }
    let consumer = RecordingConsumer()
    let reader = DescriptorReader(fileDescriptor: localSocket, closeOnEndOfFile: false, consumer: consumer)

    // Traffic through the channel guarantees libdispatch has armed the descriptor: its
    // per-descriptor entry exists, the original flags are recorded, and O_NONBLOCK is forced on.
    let ping = Data("ping".utf8)
    ping.withUnsafeBytes { buffer in
      _ = write(remoteSocket, buffer.baseAddress, buffer.count)
    }
    try await consumer.firstData.wait(timeout: 30, waitingFor: "the ping to be read")
    #expect(fcntl(localSocket, F_GETFL) & O_NONBLOCK != 0)

    reader.stop()
    #expect(await reader.finished() == .stopped)

    // Teardown must not restore blocking flags on a descriptor the channel never owned: the restore
    // is asynchronous and could land on a recycled descriptor belonging to an unrelated live channel.
    #expect(fcntl(localSocket, F_GETFL) & O_NONBLOCK != 0)
  }

  @Test
  func aBadDescriptorFailsAndStillDeliversEndOfFile() async {
    let consumer = RecordingConsumer()
    let reader = DescriptorReader(fileDescriptor: 92123, closeOnEndOfFile: false, consumer: consumer)

    #expect(await reader.finished() == .failed(errno: EBADF))
    #expect(consumer.endOfFiles == 1)
  }
}
