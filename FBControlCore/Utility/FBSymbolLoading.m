/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSymbolLoading.h"

#include <dlfcn.h>

void *FBGetSymbolFromHandle(void *handle, const char *name)
{
  void *function = FBGetSymbolFromHandleOptional(handle, name);
  NSCAssert(function, @"%s could not be located", name);
  return function;
}

void *FBGetSymbolFromHandleOptional(void *handle, const char *name)
{
  return dlsym(handle, name);
}

@implementation NSBundle (FBSymbolLoading)

- (void *)dlopenExecutablePath
{
  NSAssert(self.loaded, @"%@ is not loaded", self);
  NSString *path = [self executablePath];
  void *handle = dlopen(path.UTF8String, RTLD_LAZY);
  NSAssert(handle, @"%@ dlopen handle from %@ could not be obtained", self, path);
  return handle;
}

@end
