/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBWeakFramework;
@protocol FBControlCoreLogger;

/**
 Loads a Symbol from a Handle, using dlsym.

 @param handle the handle to obtain.
 @param name the name of the symbol.
 @return the Symbol if successful.
 */
void *FBGetSymbolFromHandle(void *handle, const char *name);

/**
 A Base Framework loader, that will ensure that the current user can load Frameworks.
 */
@interface FBControlCoreFrameworkLoader : NSObject

/**
 */
+ (instancetype)loaderWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks;

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
