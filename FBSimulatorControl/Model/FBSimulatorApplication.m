/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplication.h"

#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBTaskExecutor.h"

@interface FBSimulatorBinary ()

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSSet *architectures;

@end

@implementation FBSimulatorBinary

+ (instancetype)withName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  FBSimulatorBinary *binary = [self new];
  binary.name = name;
  binary.path = path;
  binary.architectures = architectures;
  return binary;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBSimulatorBinary *binary = [self.class new];
  binary.name = self.name;
  binary.path = self.path;
  binary.architectures = self.architectures;
  return binary;
}

- (BOOL)isEqual:(FBSimulatorBinary *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
         [object.path isEqual:self.path] &&
         [object.architectures isEqual:self.architectures];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.architectures.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Name: %@ | Path: %@ | Architectures: %@", self.name, self.path, self.architectures];
}

@end

@interface FBSimulatorApplication ()

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSString *bundleID;
@property (nonatomic, readwrite, copy) FBSimulatorBinary *binary;

@end

@implementation FBSimulatorApplication

+ (instancetype)withName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(bundleID);
  NSParameterAssert(binary);

  FBSimulatorApplication *application = [FBSimulatorApplication new];
  application.name = name;
  application.path = path;
  application.bundleID = bundleID;
  application.binary = binary;
  return application;
}

- (FBSimulatorApplication *)copyWithZone:(NSZone *)zone
{
  FBSimulatorApplication *application = [self.class new];
  application.name = self.name;
  application.path = self.path;
  application.bundleID = self.bundleID;
  application.binary = self.binary;
  return application;
}

- (BOOL)isEqual:(FBSimulatorApplication *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
         [object.path isEqual:self.path] &&
         [object.bundleID isEqual:self.bundleID] &&
         [object.binary isEqual:self.binary];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.bundleID.hash | self.binary.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Name: %@ | ID: %@ | Path: %@ | Binary (%@)", self.name, self.bundleID, self.path, self.binary];
}

@end

@implementation FBSimulatorApplication (Helpers)

+ (instancetype)applicationWithPath:(NSString *)path error:(NSError **)error;
{
  return [FBSimulatorApplication
    withName:[self appNameForPath:path]
    path:path
    bundleID:[self bundleIDForAppAtPath:path]
    binary:[self binaryForApplicationPath:path]];
}

+ (NSArray *)simulatorApplicationsFromPaths:(NSArray *)paths
{
  NSMutableArray *applications = [NSMutableArray array];
  for (NSInteger index = 0; index < paths.count; index++) {
    [applications addObject:NSNull.null];
  }

  dispatch_apply(paths.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ (size_t iteration) {
    NSString *path = paths[iteration];
    FBSimulatorApplication *application = [FBSimulatorApplication applicationWithPath:path error:nil];
    if (application) {
      @synchronized(applications) {
        applications[iteration] = application;
      }
    }
  });
  return [applications copy];
}

+ (instancetype)simulatorApplicationWithError:(NSError **)error
{
  NSString *simulatorBinaryName = [FBSimulatorControlStaticConfiguration.sdkVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]]
    ? @"Simulator"
    : @"iOS Simulator";

  NSString *appPath = [[FBSimulatorControlStaticConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];

  NSError *innerError = nil;
  FBSimulatorApplication *application = [self applicationWithPath:appPath error:&innerError];
  if (!application) {
    NSString *message = [NSString stringWithFormat:@"Could not locate Simulator Application at %@", appPath];
    return [FBSimulatorError failWithError:innerError description:message errorOut:error];
  }
  return application;
}

+ (NSArray *)simulatorSystemApplications;
{
  static dispatch_once_t onceToken;
  static NSArray *applications;
  dispatch_once(&onceToken, ^{
    NSString *systemAppsDirectory = [FBSimulatorControlStaticConfiguration.developerDirectory
      stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/Applications"];

    NSMutableArray *fullPaths = [NSMutableArray array];
    for (NSString *contentPath in [NSFileManager.defaultManager contentsOfDirectoryAtPath:systemAppsDirectory error:nil]) {
      [fullPaths addObject:[systemAppsDirectory stringByAppendingPathComponent:contentPath]];
    }
    applications = [self simulatorApplicationsFromPaths:fullPaths];
  });
  return applications;
}

+ (instancetype)systemApplicationNamed:(NSString *)appName
{
  for (FBSimulatorApplication *application in self.simulatorSystemApplications) {
    if ([application.name isEqual:appName]) {
      return application;
    }
  }
  return nil;
}

#pragma mark Private

+ (FBSimulatorBinary *)binaryForApplicationPath:(NSString *)applicationPath
{
  NSString *binaryPath = [self binaryPathForAppAtPath:applicationPath];
  return [FBSimulatorBinary binaryWithPath:binaryPath error:nil];
}

+ (NSString *)appNameForPath:(NSString *)appPath
{
  return [[appPath lastPathComponent] stringByDeletingPathExtension];
}

+ (NSString *)binaryPathForAppAtPath:(NSString *)appPath
{
  NSString *appName = [self appNameForPath:appPath];
  NSString *binaryPathIOS = [appPath stringByAppendingPathComponent:appName];
  if ([NSFileManager.defaultManager fileExistsAtPath:binaryPathIOS]) {
    return binaryPathIOS;
  }

  NSString *binaryPathMacOS = [[appPath
    stringByAppendingPathComponent:@"Contents/MacOS"]
    stringByAppendingPathComponent:appName];
  if ([NSFileManager.defaultManager fileExistsAtPath:binaryPathMacOS]) {
    return binaryPathMacOS;
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
  NSString *plistPath = [appPath stringByAppendingPathComponent:@"info.plist"];
  if ([NSFileManager.defaultManager fileExistsAtPath:plistPath]) {
    return plistPath;
  }

  plistPath = [[appPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Info.plist"];
  if ([NSFileManager.defaultManager fileExistsAtPath:plistPath]) {
    return plistPath;
  }
  return nil;
}

@end

@implementation FBSimulatorBinary (Helpers)

+ (instancetype)binaryWithPath:(NSString *)binaryPath error:(NSError **)error;
{
  return [FBSimulatorBinary
    withName:[binaryPath lastPathComponent]
    path:binaryPath
    architectures:[self binaryArchitecturesForBinaryPath:binaryPath]];
}

+ (NSSet *)binaryArchitecturesForBinaryPath:(NSString *)binaryPath
{
  NSString *fileOutput = [[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/file" arguments:@[binaryPath]]
    startSynchronouslyWithTimeout:30]
    stdOut];

  NSArray *matches = [self.fileArchRegex
    matchesInString:fileOutput
    options:0
    range:NSMakeRange(0, fileOutput.length)];

  NSMutableArray *architectures = [NSMutableArray array];
  for (NSTextCheckingResult *result in matches) {
    [architectures addObject:[fileOutput substringWithRange:[result rangeAtIndex:1]]];
  }

  return [NSSet setWithArray:architectures];
}

+ (NSRegularExpression *)fileArchRegex
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    regex = [NSRegularExpression
      regularExpressionWithPattern:@"executable (\\w+)"
      options:NSRegularExpressionAnchorsMatchLines
      error:nil];
  });
  return regex;
}

@end
