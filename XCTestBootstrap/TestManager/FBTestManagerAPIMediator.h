/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestManagerContext;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;
@protocol FBTestManagerTestReporter;

extern const NSInteger FBProtocolVersion;
extern const NSInteger FBProtocolMinimumVersion;

/**
 This is a simplified re-implementation of Apple's _IDETestManagerAPIMediator class.
 This class 'takes over' after an Application Process has been started.
 The class mediates between:
 - The Host
 - The 'testmanagerd' daemon running on iOS.
 - The 'Test Runner', the Appication in which the XCTest bundle is running.
 */
@interface FBTestManagerAPIMediator : NSObject

#pragma mark Initializers

/**
 Creates and returns a mediator with given paramenters

 @param context the Context of the Test Manager.
 @param target the target.
 @param reporter the (optional) delegate to report test progress too.
 @param logger the (optional) logger to events to.
 @param testedApplicationAdditionalEnvironment Additional Environment Variables to pass to the application under test
 @return Prepared FBTestRunnerConfiguration
 */
+ (instancetype)mediatorWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment;

#pragma mark Lifecycle

/**
 Establishes a connection between the host, testmanagerd and the Test Bundle.
 This connection is established asynchronously with a timeout applied.
 Once this connection to testmanagerd has been established, the test bundle can be executed.

 @return A future wrapping the TestManagerResult.
 */
- (FBFuture<NSNull *> *)connect;

/**
 Executes the Test Plan over the previously-established 'testmanagerd' connection.
 This should be called after `-[FBTestManagerAPIMediator connect]` has resolved.
 Test events will be delivered to the reporter in the background.

 @return A future wrapping the TestManagerResult.
 */
- (FBFuture<NSNull *> *)execute;

/**
 Terminates connection between test testmanagerd and the test bundle execution

 @return A future wrapping the TestManagerResult.
 */
- (FBFuture<NSNull *> *)disconnect;

@end

NS_ASSUME_NONNULL_END
