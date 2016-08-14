// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

@class FBSimulatorConfiguration;
@protocol FBControlCoreLogger;
@protocol FBXCTestReporter;

@interface FBTestRunConfiguration : NSObject
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readonly) FBSimulatorConfiguration *targetDeviceConfiguration;

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) NSString *testBundlePath;
@property (nonatomic, copy, readonly) NSString *runnerAppPath;
@property (nonatomic, copy, readonly) NSString *simulatorName;
@property (nonatomic, copy, readonly) NSString *simulatorOS;

- (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments workingDirectory:(NSString *)workingDirectory error:(NSError **)error;

@end
