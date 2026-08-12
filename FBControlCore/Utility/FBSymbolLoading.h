/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
 Wrappers around NSBundle.
 */
@interface NSBundle (FBSymbolLoading)

/**
 Performs a dlopen on the executable path and returns the handle, or else aborts.
 */
- (void * _Nonnull)dlopenExecutablePath;

@end
