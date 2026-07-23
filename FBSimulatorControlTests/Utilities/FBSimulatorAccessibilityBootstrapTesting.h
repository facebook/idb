/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulatorControl.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^FBSimulatorAccessibilityBootstrapPerformer)(id simulatorDevice, NSTimeInterval timeout, id<FBControlCoreLogger> _Nullable logger, NSError **error);
typedef void (^FBSimulatorAccessibilityBootstrapAttemptObserver)(BOOL ownsAttempt);

@interface FBSimulatorControlFrameworkLoader (AccessibilityBootstrapTesting)

+ (BOOL)performAccessibilityBootstrapForSimulatorDevice:(id)simulatorDevice
                                                 timeout:(NSTimeInterval)timeout
                                                  logger:(nullable id<FBControlCoreLogger>)logger
                                           providerClass:(nullable Class)providerClass
                                            sessionClass:(Class)sessionClass
                                          loadFrameworks:(BOOL)loadFrameworks
                                                   error:(NSError **)error;

+ (BOOL)bootstrapAccessibilityForSimulatorDevice:(id)simulatorDevice
                                         timeout:(NSTimeInterval)timeout
                                          logger:(nullable id<FBControlCoreLogger>)logger
                                       performer:(FBSimulatorAccessibilityBootstrapPerformer)performer
                                 attemptObserver:(nullable FBSimulatorAccessibilityBootstrapAttemptObserver)attemptObserver
                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
