/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBXCTestLogger;
@protocol FBXCTestReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 Context for the Test Run.
 Separate from configuration as these properties are not serializable.
 */
@interface FBXCTestContext : NSObject

/**
 The Context for a Test Run.

 @param reporter the reporter to report to.
 @param logger the logger to log with.
 @return a new context.
 */
+ (instancetype)contextWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger;

/**
 The Logger to log to.
 */
@property (nonatomic, strong, readonly, nullable) FBXCTestLogger *logger;

/**
 The Reporter to report to.
 */
@property (nonatomic, strong, readonly, nullable) id<FBXCTestReporter> reporter;

@end

NS_ASSUME_NONNULL_END
