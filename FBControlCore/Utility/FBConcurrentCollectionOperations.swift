/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import Foundation

private final class FBConcurrentCollectionOperations_FilterTerminal: NSObject, @unchecked Sendable {
  static let terminal = FBConcurrentCollectionOperations_FilterTerminal()
}

private final class UncheckedSendableBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}

@objc(FBConcurrentCollectionOperations)
public final class FBConcurrentCollectionOperations: NSObject {

  @objc(generate:withBlock:)
  public class func generate(_ count: UInt, withBlock block: @Sendable @escaping (UInt) -> Any) -> [Any] {
    let array = NSMutableArray(capacity: Int(count))
    for _ in 0..<count {
      array.add(NSNull())
    }

    let sendableArray = UncheckedSendableBox(array)
    DispatchQueue.concurrentPerform(iterations: Int(count)) { iteration in
      let object = block(UInt(iteration))
      objc_sync_enter(sendableArray.value)
      sendableArray.value[iteration] = object
      objc_sync_exit(sendableArray.value)
    }
    return Array(array)
  }

  @objc(map:withBlock:)
  public class func map(_ array: [Any], withBlock block: @Sendable @escaping (Any) -> Any) -> [Any] {
    let sendableArray = UncheckedSendableBox(array)
    return generate(UInt(array.count)) { index in
      return block(sendableArray.value[Int(index)])
    }
  }

  @objc(filter:predicate:)
  public class func filter(_ array: [Any], predicate: NSPredicate) -> [Any] {
    return filterMap(array, predicate: predicate) { $0 }
  }

  @objc(mapFilter:map:predicate:)
  public class func mapFilter(_ array: [Any], map block: @Sendable @escaping (Any) -> Any, predicate: NSPredicate) -> [Any] {
    let output = NSMutableArray(capacity: array.count)
    for _ in 0..<array.count {
      output.add(NSNull())
    }

    let sendableOutput = UncheckedSendableBox(output)
    let sendablePredicate = UncheckedSendableBox(predicate)
    let sendableArray = UncheckedSendableBox(array)
    DispatchQueue.concurrentPerform(iterations: array.count) { iteration in
      var object: Any = block(sendableArray.value[iteration])
      let pass = sendablePredicate.value.evaluate(with: object)
      if !pass {
        object = FBConcurrentCollectionOperations_FilterTerminal.terminal
      }
      objc_sync_enter(sendableOutput.value)
      sendableOutput.value[iteration] = object
      objc_sync_exit(sendableOutput.value)
    }

    return Array(output).filter { !($0 is FBConcurrentCollectionOperations_FilterTerminal) }
  }

  @objc(filterMap:predicate:map:)
  public class func filterMap(_ array: [Any], predicate: NSPredicate, map block: @Sendable @escaping (Any) -> Any) -> [Any] {
    let sendablePredicate = UncheckedSendableBox(predicate)
    let mapped = self.map(array) { object -> Any in
      if !sendablePredicate.value.evaluate(with: object) {
        return FBConcurrentCollectionOperations_FilterTerminal.terminal
      }
      return block(object)
    }
    return mapped.filter { !($0 is FBConcurrentCollectionOperations_FilterTerminal) }
  }
}
