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
 Loads a Symbol from a Handle, using dlsym.
 Will assert if the symbol cannot be found.

 @param handle the handle to obtain.
 @param name the name of the symbol.
 @return the Symbol if successful.
 */
void *_Nonnull FBGetSymbolFromHandle(void * _Nonnull handle, const char * _Nonnull name);

/**
 Loads a Symbol from a Handle, using dlsym.
 Will return a NULL pointer if the symbol cannot be found.

 @param handle the handle to obtain.
 @param name the name of the symbol.
 @return the Symbol if successful.
 */
void *_Nullable FBGetSymbolFromHandleOptional(void * _Nonnull handle, const char * _Nonnull name);

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

 @param logger the Logger to log events to.
 @param error any error that occurred during performing the preconditions.
 @return YES if FBSimulatorControl is usable, NO otherwise.
 */
- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError * _Nullable * _Nullable)error;

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
- (void * _Nonnull)dlopenExecutablePath;

@end
