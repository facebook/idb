// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

@class FBTestRunnerConfiguration;
@protocol FBDeviceOperator;

@protocol FBXCTestPreparationStrategy

/**
 Prepares FBTestRunnerConfiguration

 @param deviceOperator deviceOperator used to prepare test
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return FBTestRunnerConfiguration configuration used to start test
 */
- (FBTestRunnerConfiguration *)prepareTestWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator error:(NSError **)error;

@end
