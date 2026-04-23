/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import XCTest

@testable import FBControlCore

final class FBDataConsumerTests: XCTestCase {
  func testLineBufferAccumulation() {
    let consumer = FBDataBuffer.accumulatingBuffer()
    consumer.consumeData("FOO".data(using: .utf8)!)
    consumer.consumeData("BAR".data(using: .utf8)!)

    XCTAssertEqual(consumer.data(), "FOOBAR".data(using: .utf8)!)
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()
    XCTAssertEqual(consumer.data(), "FOOBAR".data(using: .utf8)!)
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
  }

  func testLineBufferAccumulationWithCapacity() {
    let consumer = FBDataBuffer.accumulatingBuffer(withCapacity: 3)
    consumer.consumeData("F".data(using: .utf8)!)
    XCTAssertEqual(consumer.lines(), ["F"])
    consumer.consumeData("O".data(using: .utf8)!)
    XCTAssertEqual(consumer.lines(), ["FO"])
    consumer.consumeData("O".data(using: .utf8)!)
    XCTAssertEqual(consumer.lines(), ["FOO"])

    consumer.consumeData("B".data(using: .utf8)!)
    XCTAssertEqual(consumer.lines(), ["OOB"])

    consumer.consumeData("AR".data(using: .utf8)!)
    XCTAssertEqual(consumer.lines(), ["BAR"])

    consumer.consumeData("ALONGSTRINGBUTIWANTAHIT".data(using: .utf8)!)
    XCTAssertEqual(consumer.lines(), ["HIT"])
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()
    XCTAssertEqual(consumer.lines(), ["HIT"])
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
  }

  func testLineBufferedConsumer() {
    var lines: [String] = []
    let consumer = FBBlockDataConsumer.synchronousLineConsumer { line in
      lines.append(line)
    }

    consumer.consumeData("FOO\n".data(using: .utf8)!)
    consumer.consumeData("BAR\n".data(using: .utf8)!)
    XCTAssertEqual(lines, ["FOO", "BAR"])
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()
    XCTAssertEqual(lines, ["FOO", "BAR"])
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("NOPE".data(using: .utf8)!)
    consumer.consumeData("NOPE".data(using: .utf8)!)
    XCTAssertEqual(lines, ["FOO", "BAR"])
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
  }

  func testLineBufferedConsumerAsync() {
    let queue = DispatchQueue(label: "testLineBufferedConsumerAsync")
    var lines: [String] = []
    let consumer = FBBlockDataConsumer.asynchronousLineConsumer { line in
      queue.sync { lines.append(line) }
    }

    consumer.consumeData("FOO\n".data(using: .utf8)!)
    consumer.consumeData("BAR\n".data(using: .utf8)!)
    usleep(1000)
    queue.sync { XCTAssertEqual(lines, ["FOO", "BAR"]) }
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()
    queue.sync { XCTAssertEqual(lines, ["FOO", "BAR"]) }
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("NOPE".data(using: .utf8)!)
    consumer.consumeData("NOPE".data(using: .utf8)!)
    queue.sync { XCTAssertEqual(lines, ["FOO", "BAR"]) }
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
  }

  func testUnbufferedConsumer() {
    let expected = "FOOBARBAZ".data(using: .utf8)!
    let actual = NSMutableData()
    let consumer = FBBlockDataConsumer.synchronousDataConsumer { incremental in
      actual.append(incremental)
    }

    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)
    consumer.consumeData("FOO".data(using: .utf8)!)
    consumer.consumeData("BAR".data(using: .utf8)!)
    consumer.consumeData("BAZ".data(using: .utf8)!)
    usleep(1000)
    XCTAssertEqual(expected, actual as Data)
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()
    XCTAssertEqual(expected, actual as Data)
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("NOPE".data(using: .utf8)!)
    consumer.consumeData("NOPE".data(using: .utf8)!)
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
    XCTAssertEqual(expected, actual as Data)
  }

  func testUnbufferedConsumerAsync() {
    let expected = "FOOBARBAZ".data(using: .utf8)!
    let actual = NSMutableData()
    let consumer = FBBlockDataConsumer.asynchronousDataConsumer { incremental in
      actual.append(incremental)
    }

    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)
    consumer.consumeData("FOO".data(using: .utf8)!)
    consumer.consumeData("BAR".data(using: .utf8)!)
    consumer.consumeData("BAZ".data(using: .utf8)!)
    usleep(1000)
    XCTAssertEqual(expected, actual as Data)
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()
    XCTAssertEqual(expected, actual as Data)
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("NOPE".data(using: .utf8)!)
    consumer.consumeData("NOPE".data(using: .utf8)!)
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
    XCTAssertEqual(expected, actual as Data)
  }

  func testConsumerAsync() {
    let expected = "FOO".data(using: .utf8)!
    let actual = NSMutableData()
    let consumeStarted = DispatchSemaphore(value: 0)
    let continueConsume = DispatchSemaphore(value: 0)
    let consumer = FBBlockDataConsumer.asynchronousDataConsumer { incremental in
      consumeStarted.signal()
      continueConsume.wait()
      actual.append(incremental)
    }

    XCTAssertEqual(0, consumer.unprocessedDataCount())
    consumer.consumeData("FOO".data(using: .utf8)!)
    consumeStarted.wait()
    XCTAssertEqual(1, consumer.unprocessedDataCount())
    continueConsume.signal()
    consumer.consumeEndOfFile()
    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
    XCTAssertEqual(0, consumer.unprocessedDataCount())
    XCTAssertEqual(expected, actual as Data)
  }

  func testLineBufferConsumption() {
    let consumer = FBDataBuffer.consumableBuffer()
    consumer.consumeData("FOO".data(using: .utf8)!)

    XCTAssertNil(consumer.consumeLineData())
    XCTAssertNil(consumer.consumeLineString())
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("BAR\n".data(using: .utf8)!)

    XCTAssertEqual(consumer.consumeLineString(), "FOOBAR")
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("BANG\nBAZ".data(using: .utf8)!)
    consumer.consumeData("\nHELLO\nHERE".data(using: .utf8)!)

    XCTAssertEqual(consumer.consumeCurrentString(), "BANG\nBAZ\nHELLO\nHERE")
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("GOODBYE".data(using: .utf8)!)
    consumer.consumeData("\nFOR\nNOW".data(using: .utf8)!)

    XCTAssertEqual(consumer.consumeCurrentData(), "GOODBYE\nFOR\nNOW".data(using: .utf8)!)
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("ILIED".data(using: .utf8)!)
    consumer.consumeData("$$SOZ\n".data(using: .utf8)!)

    XCTAssertEqual(consumer.consume(until: "$$".data(using: .utf8)!), "ILIED".data(using: .utf8)!)
    XCTAssertEqual(consumer.consumeLineString(), "SOZ")
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeData("BACKAGAIN".data(using: .utf8)!)
    consumer.consumeData("\nTHIS\nIS\nTHE\nTAIL".data(using: .utf8)!)

    XCTAssertEqual(consumer.consumeLineData(), "BACKAGAIN".data(using: .utf8)!)
    XCTAssertFalse(consumer.finishedConsuming.hasCompleted)

    consumer.consumeEndOfFile()

    XCTAssertTrue(consumer.finishedConsuming.hasCompleted)
    XCTAssertEqual(consumer.consumeLineString(), "THIS")
    XCTAssertEqual(consumer.consumeLineData(), "IS".data(using: .utf8)!)
    XCTAssertEqual(consumer.consumeLineString(), "THE")
    XCTAssertNil(consumer.consumeLineString())
    XCTAssertEqual(consumer.consumeCurrentString(), "TAIL")
  }

  func testCompositeWithCompletion() {
    let accumilating = FBDataBuffer.consumableBuffer()
    let consumable = FBDataBuffer.consumableBuffer()
    let composite = FBCompositeDataConsumer(consumers: [
      accumilating,
      consumable,
    ])

    composite.consumeData("FOO".data(using: .utf8)!)

    XCTAssertNil(consumable.consumeLineString())
    XCTAssertFalse(composite.finishedConsuming.hasCompleted)

    composite.consumeData("BAR\n".data(using: .utf8)!)

    XCTAssertEqual(consumable.consumeLineString(), "FOOBAR")
    XCTAssertNil(consumable.consumeLineString())
    XCTAssertFalse(consumable.finishedConsuming.hasCompleted)
    XCTAssertFalse(accumilating.finishedConsuming.hasCompleted)
    XCTAssertFalse(composite.finishedConsuming.hasCompleted)

    composite.consumeEndOfFile()
    XCTAssertTrue(consumable.finishedConsuming.hasCompleted)
    XCTAssertTrue(accumilating.finishedConsuming.hasCompleted)
    XCTAssertTrue(composite.finishedConsuming.hasCompleted)
  }

  func testLengthBasedConsumption() {
    let consumer = FBDataBuffer.consumableBuffer()

    consumer.consumeData("FOOBARRBAZZZ".data(using: .utf8)!)
    consumer.consumeEndOfFile()

    XCTAssertEqual(consumer.consumeLength(3), "FOO".data(using: .utf8)!)
    XCTAssertEqual(consumer.consumeLength(4), "BARR".data(using: .utf8)!)
    XCTAssertEqual(consumer.consumeLength(5), "BAZZZ".data(using: .utf8)!)
    XCTAssertNil(consumer.consumeLength(4))
    XCTAssertEqual(consumer.consumeCurrentData(), Data())
  }

  func testFutureTerminalConsumption() {
    let consumer = FBDataBuffer.notifyingBuffer()
    let queue = DispatchQueue.global(qos: .userInitiated)
    let doneExpectation = XCTestExpectation(description: "Resolved All")

    consumer
      .consumeAndNotify(when: "$$".data(using: .utf8)!)
      .onQueue(
        queue,
        fmap: { (result: Any) -> FBFuture<AnyObject> in
          XCTAssertEqual(result as! NSData, "FOO".data(using: .utf8)! as NSData)
          return consumer.consumeAndNotify(when: "\n".data(using: .utf8)!) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        queue,
        doOnResolved: { (result: Any) in
          XCTAssertEqual(result as! NSData, "BAR".data(using: .utf8)! as NSData)
          doneExpectation.fulfill()
        })

    consumer.consumeData("FOO$$BAR\nBAZ".data(using: .utf8)!)
    consumer.consumeEndOfFile()

    wait(for: [doneExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }

  func testHeaderConsumption() {
    let consumer = FBDataBuffer.notifyingBuffer()
    let queue = DispatchQueue.global(qos: .userInitiated)
    let doneExpectation = XCTestExpectation(description: "Resolved All")

    let payloadData = "FOO BAR BAZ".data(using: .utf8)!
    let payloadLength = UInt(payloadData.count)
    var payloadLengthValue = payloadLength
    let headerData = Data(bytes: &payloadLengthValue, count: MemoryLayout<UInt>.size)

    consumer
      .consumeHeaderLength(
        UInt(MemoryLayout<UInt>.size),
        derivedLength: { data in
          XCTAssertEqual(data.count, MemoryLayout<UInt>.size)
          var readPayloadLength: UInt = 0
          (data as NSData).getBytes(&readPayloadLength, length: MemoryLayout<UInt>.size)
          XCTAssertEqual(readPayloadLength, payloadLength)
          return UInt(readPayloadLength)
        }
      )
      .onQueue(
        queue,
        doOnResolved: { result in
          XCTAssertEqual(result as Data, payloadData)
          doneExpectation.fulfill()
        })

    consumer.consumeData(headerData)
    consumer.consumeData(payloadData)
    consumer.consumeEndOfFile()

    wait(for: [doneExpectation], timeout: FBControlCoreGlobalConfiguration.fastTimeout)
  }
}
