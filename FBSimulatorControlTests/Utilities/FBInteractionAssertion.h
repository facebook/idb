/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@protocol FBInteraction;

/**
 Assertion Helpers for validating `FBInteraction` results.
 */
@interface FBInteractionAssertion : NSObject

/**
 Creates and returns an Interaction, reporting to the specified test case.

 @param testCase the XCTestCase to report to.
 */
+ (instancetype)withTestCase:(XCTestCase *)testCase;

/**
 Peforms the provided Interaction and validates that the interaction was successful.

 @param interaction the interaction to perform.
 */
- (void)assertPerformSuccess:(id<FBInteraction>)interaction;

@end
