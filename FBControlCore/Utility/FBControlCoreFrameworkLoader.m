/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreFrameworkLoader.h"

#import "FBControlCoreLogger.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreError.h"
#import "FBWeakFrameworkLoader.h"

#include <dlfcn.h>

void *FBGetSymbolFromHandle(void *handle, const char *name)
{
  void *function = dlsym(handle, name);
  NSCAssert(function, @"%s could not be located", name);
  return function;
}

@implementation FBControlCoreFrameworkLoader

#pragma mark Initializers

+ (instancetype)loaderWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks
{
  return [[self alloc] initWithName:frameworkName frameworks:frameworks];
}

- (instancetype)initWithName:(NSString *)frameworkName frameworks:(NSArray<FBWeakFramework *> *)frameworks
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _frameworkName = frameworkName;
  _frameworks = frameworks;
  _hasLoadedFrameworks = NO;

  return self;
}

#pragma mark Public Methods.

- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (self.hasLoadedFrameworks) {
    return YES;
  }

  if ([NSUserName() isEqualToString:@"root"]) {
    return [[FBControlCoreError
      describeFormat:@"The Frameworks for %@ cannot be loaded from the root user. Don't run this as root.", self.frameworkName]
      failBool:error];
  }
  BOOL result = [FBWeakFrameworkLoader loadPrivateFrameworks:self.frameworks logger:logger error:error];
  if (result) {
    _hasLoadedFrameworks = YES;
  }
  return result;
}

- (void)loadPrivateFrameworksOrAbort
{
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  NSError *error = nil;
  BOOL success = [self loadPrivateFrameworks:logger.debug error:&error];
  if (success) {
    return;
  }
  NSString *message = [NSString stringWithFormat:@"Failed to private frameworks for %@ with error %@", self.frameworkName, error];

  // Log the message.
  [logger.error log:message];
  // Assertions give a better message in the crash report.
  NSAssert(NO, message);
  // However if assertions are compiled out, then we still need to abort.
  abort();
}

@end

@implementation NSBundle (FBControlCoreFrameworkLoader)

- (void *)dlopenExecutablePath
{
  NSAssert(self.loaded, @"%@ is not loaded", self);
  NSString *path = [self executablePath];
  void *handle = dlopen(path.UTF8String, RTLD_LAZY);
  NSAssert(handle, @"%@ dlopen handle from %@ could not be obtained", self, path);
  return handle;
}

@end
