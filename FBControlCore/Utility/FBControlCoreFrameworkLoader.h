/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBWeakFramework;
@protocol FBControlCoreLogger;

/**
 Loads a Symbol from a Handle, using dlsym.
 Will assert if the symbol cannot be found.

 @param handle the handle to obtain.
 @param name the name of the symbol.
 @return the Symbol if successful.
 */
void *FBGetSymbolFromHandle(void *handle, const char *name);

/**
 Loads a Symbol from a Handle, using dlsym.
 Will return a NULL pointer if the symbol cannot be found.

 @param handle the handle to obtain.
 @param name the name of the symbol.
 @return the Symbol if successful.
 */
void *FBGetSymbolFromHandleOptional(void *handle, const char *name);

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
+ (instancetype)loaderWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks;

/**
 The Designated Initializer

 @param frameworkName the name of the loading framework.
 @param frameworks the framework dependencies
 @return a new Framework Loader
 */
- (instancetype)initWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks;

#pragma mark Properties

/**
 The Named set of Frameworks.
 */
@property (nonatomic, copy, readonly) NSString *frameworkName;

/**
 The Frameworks to load.
 */
@property (nonatomic, copy, readonly) NSArray<FBWeakFramework *> *frameworks;

/**
 YES if the Frameworks are loaded, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL hasLoadedFrameworks;

#pragma mark Public Methods

/**
 Confirms that the current user can load Frameworks.
 Subclasses should load the frameworks upon which they depend.

 @param logger the Logger to log events to.
 @param error any error that occurred during performing the preconditions.
 @return YES if FBSimulatorControl is usable, NO otherwise.
 */
- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Calls +[FBControlCore loadPrivateFrameworks:error], aborting in the event the Frameworks could not be loaded
 */
- (void)loadPrivateFrameworksOrAbort;

@end

/**
 Wrappers around NSBundle.
 */
@interface NSBundle (FBControlCoreFrameworkLoader)

/**
 Performs a dlopen on the executable path and returns the handle, or else aborts.
 */
- (void *)dlopenExecutablePath;

@end

NS_ASSUME_NONNULL_END
