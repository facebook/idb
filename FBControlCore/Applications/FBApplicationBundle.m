/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationBundle.h"

#import "FBBinaryDescriptor.h"
#import "FBBinaryParser.h"
#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBTask.h"
#import "FBTaskBuilder.h"

@implementation FBApplicationBundle

#pragma mark Initializers

+ (instancetype)applicationWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID
{
  return [[self alloc] initWithName:name path:path bundleID:bundleID binary:nil];
}

+ (nullable instancetype)applicationWithPath:(NSString *)path error:(NSError **)error
{
  if (!path) {
    return [[FBControlCoreError
      describe:@"Nil file path provided for application"]
      fail:error];
  }
  NSString *appName = [self appNameForPath:path];
  if (!appName) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain app name for path %@", path]
      fail:error];
  }
  NSError *innerError = nil;
  NSString *bundleID = [self infoPlistKey:@"CFBundleIdentifier" forAppAtPath:path error:&innerError];
  if (!bundleID) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain Bundle ID for app at path %@: %@", path, innerError]
      fail:error];
  }
  FBBinaryDescriptor *binary = [self binaryForApplicationPath:path error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError describeFormat:@"Could not obtain binary for app at path %@", path] causedBy:innerError] fail:error];
  }
  return [[FBApplicationBundle alloc] initWithName:appName path:path bundleID:bundleID binary:binary];
}

#pragma mark Private

+ (FBBinaryDescriptor *)binaryForApplicationPath:(NSString *)applicationPath error:(NSError **)error
{
  NSError *innerError = nil;
  NSString *binaryPath = [self binaryPathForAppAtPath:applicationPath error:&innerError];
  if (!binaryPath) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain binary path for application at path %@: %@", applicationPath, innerError]
      fail:error];
  }

  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:binaryPath error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError
      describeFormat:@"Could not obtain binary info for binary at path %@", binaryPath]
      causedBy:innerError]
      fail:error];
  }
  return binary;
}

+ (NSString *)appNameForPath:(NSString *)appPath
{
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[self infoPlistPathForAppAtPath:appPath error:nil]];
  NSString *bundleName = infoPlist[@"CFBundleName"];
  return bundleName ?: appPath.lastPathComponent.stringByDeletingPathExtension;
}

+ (NSString *)binaryPathForAppAtPath:(NSString *)appPath error:(NSError **)error
{
  NSString *binaryName = [self infoPlistKey:@"CFBundleExecutable" forAppAtPath:appPath error:error];
  if (!binaryName) {
    return nil;
  }
  NSArray *paths = @[
    [appPath stringByAppendingPathComponent:binaryName],
    [[appPath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:binaryName]
  ];

  for (NSString *path in paths) {
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
      return path;
    }
  }
  return nil;
}

+ (NSString *)infoPlistKey:(NSString *)key forAppAtPath:(NSString *)appPath error:(NSError **)error
{
  NSString *infoPlistPath = [self infoPlistPathForAppAtPath:appPath error:error];
  if (!infoPlistPath) {
    return nil;
  }
  NSDictionary<NSString *, NSString *> *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
  if (!infoPlist) {
    return [[FBControlCoreError
      describeFormat:@"Could not load Info.plist at path %@", infoPlistPath]
      fail:error];
  }
  NSString *value = infoPlist[key];
  if (!value) {
    return [[FBControlCoreError
      describeFormat:@"Could not load key %@ in Info.plist, values %@", key, [FBCollectionInformation oneLineDescriptionFromArray:infoPlist.allKeys]]
      fail:error];
  }
  return value;
}

+ (NSString *)infoPlistPathForAppAtPath:(NSString *)appPath error:(NSError **)error
{
  NSArray *paths = @[
    [appPath stringByAppendingPathComponent:@"info.plist"],
    [[appPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Info.plist"]
  ];

  for (NSString *path in paths) {
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
      return path;
    }
  }
  return [[FBControlCoreError
    describeFormat:@"Could not find an Info.plist at any of the expected locations %@", [FBCollectionInformation oneLineDescriptionFromArray:paths]]
    fail:error];
}

@end
