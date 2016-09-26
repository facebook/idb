/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationDescriptor.h"

#import "FBControlCoreError.h"
#import "FBBinaryDescriptor.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBCollectionInformation.h"
#import "FBBinaryParser.h"

@implementation FBApplicationDescriptor

+ (nullable instancetype)applicationWithPath:(NSString *)path error:(NSError **)error;
{
  NSMutableDictionary *applicationCache = self.applicationCache;
  FBApplicationDescriptor *application = applicationCache[path];
  if (application) {
    return application;
  }

  NSError *innerError = nil;
  application = [FBApplicationDescriptor createApplicationWithPath:path error:&innerError];
  if (!application) {
    return [FBControlCoreError failWithError:innerError errorOut:error];
  }
  applicationCache[path] = application;
  return application;
}

+ (nullable instancetype)systemApplicationNamed:(NSString *)appName error:(NSError **)error
{
  return [self applicationWithPath:[self pathForSystemApplicationNamed:appName] error:error];
}

+ (instancetype)xcodeSimulator;
{
  NSError *error = nil;
  FBApplicationDescriptor *application = [self applicationWithPath:self.pathForSimulatorApplication error:&error];
  NSAssert(application, @"Expected to be able to build an Application, got an error %@", application);
  return application;
}

#pragma mark Private

+ (NSString *)pathForSimulatorApplication
{
  NSString *simulatorBinaryName = [FBControlCoreGlobalConfiguration.iosSDKVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]]
    ? @"Simulator"
    : @"iOS Simulator";

  return [[FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];
}

+ (NSString *)pathForSystemApplicationNamed:(NSString *)name
{
  return [[[FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/Applications"]
    stringByAppendingPathComponent:name]
    stringByAppendingPathExtension:@"app"];
}

+ (instancetype)createApplicationWithPath:(NSString *)path error:(NSError **)error;
{
  if (!path) {
    return [[FBControlCoreError describe:@"Path is nil for Application"] fail:error];
  }
  NSString *appName = [self appNameForPath:path];
  if (!appName) {
    return [[FBControlCoreError describeFormat:@"Could not obtain app name for path %@", path] fail:error];
  }
  NSString *bundleID = [self bundleIDForAppAtPath:path];
  if (!bundleID) {
    return [[FBControlCoreError describeFormat:@"Could not obtain Bundle ID for app at path %@", path] fail:error];
  }
  NSError *innerError = nil;
  FBBinaryDescriptor *binary = [self binaryForApplicationPath:path error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError describeFormat:@"Could not obtain binary for app at path %@", path] causedBy:innerError] fail:error];
  }

  return [[FBApplicationDescriptor alloc] initWithName:appName path:path bundleID:bundleID binary:binary];
}

+ (NSMutableDictionary *)applicationCache
{
  static dispatch_once_t onceToken;
  static NSMutableDictionary *cache;
  dispatch_once(&onceToken, ^{
    cache = [NSMutableDictionary dictionary];
  });
  return cache;
}

+ (FBBinaryDescriptor *)binaryForApplicationPath:(NSString *)applicationPath error:(NSError **)error
{
  NSString *binaryPath = [self binaryPathForAppAtPath:applicationPath];
  if (!binaryPath) {
    return [[FBControlCoreError describeFormat:@"Could not obtain binary path for application at path %@", applicationPath] fail:error];
  }

  NSError *innerError = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:binaryPath error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError describeFormat:@"Could not obtain binary info for binary at path %@", binaryPath] causedBy:innerError] fail:error];
  }
  return binary;
}

+ (NSString *)appNameForPath:(NSString *)appPath
{
  return [[appPath lastPathComponent] stringByDeletingPathExtension];
}

+ (NSString *)binaryNameForAppAtPath:(NSString *)appPath
{
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[self infoPlistPathForAppAtPath:appPath]];
  return infoPlist[@"CFBundleExecutable"];
}

+ (NSString *)binaryPathForAppAtPath:(NSString *)appPath
{
  NSString *binaryName = [self binaryNameForAppAtPath:appPath];
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

+ (NSString *)bundleIDForAppAtPath:(NSString *)appPath
{
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[self infoPlistPathForAppAtPath:appPath]];
  return infoPlist[@"CFBundleIdentifier"];
}

+ (NSString *)infoPlistPathForAppAtPath:(NSString *)appPath
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
  return nil;
}

@end
