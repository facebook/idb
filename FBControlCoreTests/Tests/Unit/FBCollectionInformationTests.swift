/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

/// No `NSObject` root, so no key-value coding.
private final class SwiftRootClass: CustomStringConvertible {
  var description: String { "a swift root class" }
}

private final class ObjectiveCRootedClass: NSObject {
  override var description: String { "an objective-c rooted class" }
}

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

  @Test
  func oneLineDescription_FallsBackToTheElementsWhenTheKeyPathIsNotPerElement() {
    let elements: [Any] = ["alpha", "bet"]
    #expect((FBCollectionInformation.oneLineDescription(from: elements, atKeyPath: "@count")) == ("[alpha, bet]"))
  }

  @Test
  func oneLineDescription_DescribesAClassWithNoObjectiveCRoot() {
    #expect((FBCollectionInformation.oneLineDescription(from: [SwiftRootClass()])) == ("[a swift root class]"))
  }
}
