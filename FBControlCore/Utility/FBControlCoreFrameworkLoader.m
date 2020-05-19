/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBControlCoreFrameworkLoader.h"

#import "FBControlCoreLogger.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreError.h"
#import "FBWeakFrameworkLoader.h"

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
  BOOL result = [FBWeakFrameworkLoader loadPrivateFrameworks:self.frameworks logger:logger error:error];
  if (result) {
    _hasLoadedFrameworks = YES;
  }
  return result;
}

- (void)loadPrivateFrameworksOrAbort
{
  id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"framework_loader"];
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
