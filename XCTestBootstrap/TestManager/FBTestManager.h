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
@class FBTestManagerResult;
@protocol FBiOSTarget;
@protocol FBControlCoreLogger;
@protocol FBTestManagerTestReporter;

/**
 Manages a connection with the 'testmanagerd' daemon.
 */
@interface FBTestManager : NSObject <FBiOSTargetContinuation>

/**
 Creates and returns a test manager with given paramenters.

 @param context the Context of the Test Manager.
 @param iosTarget a ios target used to handle device.
 @param reporter an optional reporter to report test progress to.
 @param logger the logger object to log events to, may be nil.
 @param testedApplicationAdditionalEnvironment additional environment var passed, when launching application
 @return Prepared FBTestManager
 */
+ (instancetype)testManagerWithContext:(FBTestManagerContext *)context iosTarget:(id<FBiOSTarget>)iosTarget reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment;

/**
 Connects to the 'testmanagerd' daemon and to the test bundle.

 @return A TestManager Result if an early-error occured, nil otherwise.
 */
- (FBFuture<FBTestManagerResult *> *)connect;

/**
 Connects to the 'testmanagerd' daemon and to the test bundle.

 @return A TestManager Result if an early-error occured, nil otherwise.
 */
- (FBFuture<FBTestManagerResult *> *)execute;

@end

NS_ASSUME_NONNULL_END
