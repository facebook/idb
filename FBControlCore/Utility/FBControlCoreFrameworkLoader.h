/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBWeakFramework;
@protocol FBControlCoreLogger;

/**
 A Base Framework loader, that will ensure that the current user can load Frameworks.
 */
@interface FBControlCoreFrameworkLoader : NSObject

#pragma mark Initializers

/**
 The Designated Initializer

 @param frameworkName the name of the loading framework.
 @param frameworks the framework dependencies
 @return a new Framework Loader
 */
+ (nonnull instancetype)loaderWithName:(nonnull NSString *)frameworkName frameworks:(nonnull NSArray<FBWeakFramework *> *)frameworks;

/**
 The Designated Initializer

 @param frameworkName the name of the loading framework.
 @param frameworks the framework dependencies
 @return a new Framework Loader
 */
- (nonnull instancetype)initWithName:(nonnull NSString *)frameworkName frameworks:(nonnull NSArray<FBWeakFramework *> *)frameworks;

#pragma mark Properties

/**
 The Named set of Frameworks.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *frameworkName;

/**
 The Frameworks to load.
 */
@property (nonnull, nonatomic, readonly, copy) NSArray<FBWeakFramework *> *frameworks;

/**
 YES if the Frameworks are loaded, NO otherwise.
 */
@property (nonatomic, readonly, assign) BOOL hasLoadedFrameworks;

#pragma mark Public Methods

/**
 Confirms that the current user can load Frameworks.
 Subclasses should load the frameworks upon which they depend.

 @param logger the Logger to log events to. nil loads silently: diagnostics go to the os_log-only
 default logger (see FBControlCoreGlobalConfiguration.defaultLogger).
 @param error any error that occurred during performing the preconditions.
 @return YES if FBSimulatorControl is usable, NO otherwise.
 */
- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError * _Nullable * _Nullable)error;

@end
