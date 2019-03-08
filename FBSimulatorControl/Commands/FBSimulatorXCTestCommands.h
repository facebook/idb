/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBApplicationTestConfiguration;
@class FBSimulator;
@class FBTestBundle;
@class FBTestLaunchConfiguration;
@protocol FBTestManagerTestReporter;
@protocol FBXCTestReporter;

/**
 Commands to perform on a Simulator, related to XCTest.
 */
@protocol FBSimulatorXCTestCommands <NSObject, FBXCTestCommands, FBiOSTargetCommand>

/**
 Starts testing application using test bundle.

 @param testLaunchConfiguration configuration used to launch test.
 @param reporter the reporter to report to.
 @param logger the logger to log to.
 @param workingDirectory xctest working directory.
 @return a Future, wrapping an in-flight Test Operation.
 */
- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger workingDirectory:(nullable NSString *)workingDirectory;

/**
 Runs the specified Application Test.

 @param configuration the configuration to use
 @param reporter the reporter to report to.
 @return A future that resolves when the Application Test has completed.
 */
- (FBFuture<NSNull *> *)runApplicationTest:(FBApplicationTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter;

@end

/**
 The implementation of the FBSimulatorXCTestCommands instance.
 */
@interface FBSimulatorXCTestCommands : NSObject <FBSimulatorXCTestCommands>

@end

NS_ASSUME_NONNULL_END
