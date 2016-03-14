/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBTestManager;
@protocol FBXCTestPreparationStrategy;
@protocol FBDeviceOperator;

/**
 Strategy used to run XCTest and attach testmanagerd daemon to it.
 */
@interface FBXCTestRunStrategy : NSObject

/**
 Convenience constructor

 @param deviceOperator device operator used to run tests
 @param testPrepareStrategy test preparation strategy used to prepare device to test
 @return operator
 */
+ (instancetype)strategyWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator testPrepareStrategy:(id<FBXCTestPreparationStrategy>)testPrepareStrategy;

/**
 Starts testing session

 @param attributes additional attributes used to start test runner
 @param environment additional environment used to start test runner
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return testManager if the operation succeeds, otherwise nil.
 */
- (FBTestManager *)startTestManagerWithAttributes:(NSArray *)attributes environment:(NSDictionary *)environment error:(NSError **)error;

@end
