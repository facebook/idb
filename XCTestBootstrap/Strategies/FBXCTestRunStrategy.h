// Copyright 2004-present Facebook. All Rights Reserved.

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
