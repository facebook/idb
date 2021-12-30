/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTestBootstrap/FBLogicXCTestReporter.h>
#import <XCTestBootstrap/FBXCTestReporter.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

/**
 This adapter parses streams of events in JSON and invokes
 the corresponding methods in the provided FBXCTestReporter
 */
@interface FBLogicReporterAdapter : NSObject <FBLogicXCTestReporter>

/**
 The Designated Initializer.

 @param reporter the reporter to report to.
 @param logger an optional logger to log to,
 @return a new FBLogicXCTestReporter instance.
 */
- (instancetype)initWithReporter:(id<FBXCTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
