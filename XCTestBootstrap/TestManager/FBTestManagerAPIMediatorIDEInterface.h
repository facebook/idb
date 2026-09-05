/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBTestManagerAPIMediator;
@class FBTestManagerContext;

@protocol FBControlCoreLogger;
@protocol FBXCTestReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 Implements the private XCTest `XCTestManager_IDEInterface` / `XCTMessagingChannel_RunnerToIDE` callback surface that the test runner and `testmanagerd` call over the DTX channel. Process launch and termination requests are forwarded to `FBTestManagerAPIMediator`.
 */
@interface FBTestManagerAPIMediatorIDEInterface : NSObject

#pragma mark Initializers

/**
 Constructs the IDE interface delegate.

 @param mediator the Swift mediator that owns orchestration and application lifecycle.
 @param context the Context of the Test Manager.
 @param reporter the delegate to report test progress to.
 @param logger the logger to log events to.
 */
- (instancetype)initWithMediator:(FBTestManagerAPIMediator *)mediator context:(FBTestManagerContext *)context reporter:(id<FBXCTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
