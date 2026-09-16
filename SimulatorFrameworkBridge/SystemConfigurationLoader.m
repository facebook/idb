/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "SystemConfigurationLoader.h"

#import <dlfcn.h>

static void *(^testLoad)(void);
static void *(^testLookup)(void *, const char *);

void *FBSystemConfigurationLoad(void)
{
  return testLoad ? testLoad() : dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
}

void *FBSystemConfigurationLookup(void *library, const char *symbol)
{
  return testLookup ? testLookup(library, symbol) : dlsym(library, symbol);
}

void FBSystemConfigurationSetLoaderForTesting(void *(^load)(void), void *(^lookup)(void *, const char *))
{
  testLoad = [load copy];
  testLookup = [lookup copy];
}
