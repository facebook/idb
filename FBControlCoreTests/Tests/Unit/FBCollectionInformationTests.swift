/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

/// A class with no superclass at all, and so no key-value coding: what an idb type becomes once
/// it stops inheriting from `NSObject`.
private final class SwiftRootClass: CustomStringConvertible {
  var description: String { "a swift root class" }
}

private final class ObjectiveCRootedClass: NSObject {
  override var description: String { "an objective-c rooted class" }
}

/// `oneLineDescription(from:)` is how a collection reaches a log line or an error message
/// throughout idb, so what it does to each kind of element is a contract rather than an
/// implementation detail.
@Suite
struct FBCollectionInformationTests {

  @Test
  func oneLineDescription_DescribesEachElementAsItsOwnClassDoes() {
    let elements: [Any] = [ObjectiveCRootedClass(), NSNumber(value: 1), NSNull()]
    #expect(
      (FBCollectionInformation.oneLineDescription(from: elements))
        == ("[an objective-c rooted class, 1, <null>]"))
  }

  @Test
  func oneLineDescription_ResolvesAPerElementKeyPath() {
    let elements: [Any] = ["alpha", "bet"]
    #expect((FBCollectionInformation.oneLineDescription(from: elements, atKeyPath: "length")) == ("[5, 3]"))
  }

  /// A key path that resolves to a scalar rather than to one value per element — an aggregate
  /// operator is the way to get one — describes the elements themselves instead.
  @Test
  func oneLineDescription_FallsBackToTheElementsWhenTheKeyPathIsNotPerElement() {
    let elements: [Any] = ["alpha", "bet"]
    #expect((FBCollectionInformation.oneLineDescription(from: elements, atKeyPath: "@count")) == ("[alpha, bet]"))
  }

  /// BUG: it does not describe one, it kills the process. The elements are resolved through
  /// `-[NSArray valueForKeyPath:]`, and a class with no Objective-C root has no key-value coding to
  /// answer that with, so the runtime aborts rather than raising something catchable. Flipped in
  /// the following commit.
  @Test
  func oneLineDescription_DescribesAClassWithNoObjectiveCRoot() async {
    await #expect(processExitsWith: .signal(SIGABRT)) {
      _ = FBCollectionInformation.oneLineDescription(from: [SwiftRootClass()])
    }
  }
}
