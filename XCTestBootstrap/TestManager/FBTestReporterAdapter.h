/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestPrivate/XCTestManager_IDEInterface-Protocol.h>

@protocol FBXCTestReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 Converts Low-Level XCTestManager_IDEInterface Messages to their counterparts in FBXCTestReporter.
 */
@interface FBTestReporterAdapter : NSObject<XCTestManager_IDEInterface>

/**
 Constructs a Report Adapter.

 @param reporter the reporter to report to.
 @return a new adapter.
 */
+ (instancetype)withReporter:(id<FBXCTestReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
