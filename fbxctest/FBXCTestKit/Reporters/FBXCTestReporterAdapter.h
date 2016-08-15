// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTestBootstrap/FBTestManagerTestReporter.h>

@protocol FBXCTestReporter;

@interface FBXCTestReporterAdapter : NSObject <FBTestManagerTestReporter>

+ (instancetype)adapterWithReporter:(id<FBXCTestReporter>)reporter;

@end
