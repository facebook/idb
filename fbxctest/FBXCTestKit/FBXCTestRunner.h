// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

@class FBTestRunConfiguration;

@interface FBXCTestRunner : NSObject

+ (instancetype)testRunnerWithConfiguration:(FBTestRunConfiguration *)configuration;

- (BOOL)executeTestsWithError:(NSError **)error;

@end
