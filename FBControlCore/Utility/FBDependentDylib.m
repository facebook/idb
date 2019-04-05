/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

/* Portions Copyright © Microsoft Corporation. */

#import "FBDependentDylib.h"
#import "FBControlCoreError.h"
#import "FBXcodeConfiguration.h"
#import "FBControlCoreLogger.h"
#import <dlfcn.h>

@interface FBDependentDylib ()

@property (nonatomic, copy, readonly) NSString *path;

@end

@implementation FBDependentDylib


#pragma mark Initializers

+ (instancetype)dependentWithRelativePath:(NSString *)relativePath
{
  return [[FBDependentDylib alloc] initWithRelativePath:relativePath];
}

- (instancetype)initWithRelativePath:(NSString *)relativePath
{
  self = [super init];
  if (self) {
    NSString *developerDirectory = FBXcodeConfiguration.developerDirectory;
    NSString *joined = [developerDirectory stringByAppendingPathComponent:relativePath];
    _path = [joined stringByStandardizingPath];
  }
  return self;
}

+ (instancetype)dependentWithAbsolutePath:(NSString *)absolutePath
{
    return [[FBDependentDylib alloc] initWithAbsolutePath:absolutePath];
}

- (instancetype)initWithAbsolutePath:(NSString *)absolutePath
{
    self = [super init];
    if (self) {
        _path = [absolutePath stringByStandardizingPath];
    }
    return self;
}

#pragma mark Public

- (BOOL)loadWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSURL *url = [NSURL fileURLWithPath:self.path];
  const char *cFileSystemRep = [url fileSystemRepresentation];
  void *handle = dlopen(cFileSystemRep, RTLD_NOW|RTLD_GLOBAL);
  [logger.debug logFormat:@"Attempting to load: %s", cFileSystemRep];
  if (!handle) {
    NSString *message = [NSString stringWithFormat:@"Could not load dylib %@ with dlopen: %s",
                         self.path, dlerror()];
    [logger.debug logFormat:@"%@", message];
    return [FBControlCoreError failBoolWithErrorMessage:message
                                               errorOut:error];
  } else {
    [logger.debug logFormat:@"Loaded %@", [self.path lastPathComponent]];
    return YES;
  }
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@: %@>",
          NSStringFromClass([self class]), self.path];
}

@end
