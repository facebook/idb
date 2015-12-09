/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplication.h"

#import "FBConcurrentCollectionOperations.h"
#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBTaskExecutor.h"

@implementation FBSimulatorBinary

- (instancetype)initWithName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(architectures);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _path = path;
  _architectures = architectures;

  return self;
}

+ (instancetype)withName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  if (!name || !path || !architectures) {
    return nil;
  }
  return [[self alloc] initWithName:name path:path architectures:architectures];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBSimulatorBinary alloc]
    initWithName:self.name
    path:self.path
    architectures:self.architectures];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  _path = [coder decodeObjectForKey:NSStringFromSelector(@selector(path))];
  _architectures = [coder decodeObjectForKey:NSStringFromSelector(@selector(architectures))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:self.path forKey:NSStringFromSelector(@selector(path))];
  [coder encodeObject:self.architectures forKey:NSStringFromSelector(@selector(architectures))];
}

#pragma mark NSObject

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

@implementation FBSimulatorApplication

- (instancetype)initWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(bundleID);
  NSParameterAssert(binary);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _path = path;
  _bundleID = bundleID;
  _binary = binary;

  return self;
}

+ (instancetype)withName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary
{
  if (!name || !path || !bundleID || !binary) {
    return nil;
  }
  return [[self alloc] initWithName:name path:path bundleID:bundleID binary:binary];
}

#pragma mark NSCopying

- (FBSimulatorApplication *)copyWithZone:(NSZone *)zone
{
  return [[FBSimulatorApplication alloc]
    initWithName:self.name
    path:self.path
    bundleID:self.bundleID
    binary:self.binary];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSString *name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  NSString *path = [coder decodeObjectForKey:NSStringFromSelector(@selector(path))];
  NSString *bundleID = [coder decodeObjectForKey:NSStringFromSelector(@selector(bundleID))];
  FBSimulatorBinary *binary = [coder decodeObjectForKey:NSStringFromSelector(@selector(binary))];

  return [[FBSimulatorApplication alloc]
    initWithName:name
    path:path
    bundleID:bundleID
    binary:binary];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:self.path forKey:NSStringFromSelector(@selector(path))];
  [coder encodeObject:self.bundleID forKey:NSStringFromSelector(@selector(bundleID))];
  [coder encodeObject:self.binary forKey:NSStringFromSelector(@selector(binary))];
}

#pragma mark NSObject

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
  if (!path) {
    return [[FBSimulatorError describe:@"Path is nil for Application"] fail:error];
  }
  NSString *appName = [self appNameForPath:path];
  if (!appName) {
    return [[FBSimulatorError describeFormat:@"Could not obtain app name for path %@", path] fail:error];
  }
  NSString *bundleID = [self bundleIDForAppAtPath:path];
  if (!bundleID) {
    return [[FBSimulatorError describeFormat:@"Could not obtain Bundle ID for app at path %@", path] fail:error];
  }
  NSError *innerError = nil;
  FBSimulatorBinary *binary = [self binaryForApplicationPath:path error:&innerError];
  if (!binary) {
    return [[[FBSimulatorError describeFormat:@"Could not obtain binary for app at path %@", path] causedBy:innerError] fail:error];
  }

  return [[FBSimulatorApplication alloc] initWithName:appName path:path bundleID:bundleID binary:binary];
}

+ (NSArray *)simulatorApplicationsFromPaths:(NSArray *)paths
{
  return [FBConcurrentCollectionOperations
    generate:paths.count
    withBlock:^ FBSimulatorApplication * (NSUInteger index) {
      return [FBSimulatorApplication applicationWithPath:paths[index] error:nil];
    }];
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

+ (instancetype)systemApplicationNamed:(NSString *)appName error:(NSError **)error
{
  NSMutableDictionary *applicationCache = self.applicationCache;
  NSString *path = [self pathForSystemApplicationNamed:appName];
  FBSimulatorApplication *application = applicationCache[path];
  if (application) {
    return application;
  }

  NSError *innerError = nil;
  application = [FBSimulatorApplication applicationWithPath:path error:&innerError];
  if (!application) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  applicationCache[path] = application;
  return application;
}

#pragma mark Private

+ (NSString *)pathForSystemApplicationNamed:(NSString *)name
{
  return [[[FBSimulatorControlStaticConfiguration.developerDirectory
    stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/Applications"]
    stringByAppendingPathComponent:name]
    stringByAppendingPathExtension:@"app"];
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

+ (FBSimulatorBinary *)binaryForApplicationPath:(NSString *)applicationPath error:(NSError **)error
{
  NSString *binaryPath = [self binaryPathForAppAtPath:applicationPath];
  if (!binaryPath) {
    return [[FBSimulatorError describeFormat:@"Could not obtain binary path for application at path %@", applicationPath] fail:error];
  }

  NSError *innerError = nil;
  FBSimulatorBinary *binary = [FBSimulatorBinary binaryWithPath:binaryPath error:&innerError];
  if (!binary) {
    return [[[FBSimulatorError describeFormat:@"Could not obtain binary info for binary at path %@", binaryPath] causedBy:innerError] fail:error];
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
  NSString *binaryPathIOS = [appPath stringByAppendingPathComponent:binaryName];
  if ([NSFileManager.defaultManager fileExistsAtPath:binaryPathIOS]) {
    return binaryPathIOS;
  }

  NSString *binaryPathMacOS = [[appPath
    stringByAppendingPathComponent:@"Contents/MacOS"]
    stringByAppendingPathComponent:binaryName];
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
  NSError *innerError = nil;
  NSSet *archs = [self binaryArchitecturesForBinaryPath:binaryPath error:&innerError];
  if (archs.count < 1) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  return [[FBSimulatorBinary alloc]
    initWithName:[self binaryNameForBinaryPath:binaryPath]
    path:binaryPath
    architectures:archs];
}

+ (NSString *)binaryNameForBinaryPath:(NSString *)binaryPath
{
  return binaryPath.lastPathComponent;
}

+ (NSSet *)binaryArchitecturesForBinaryPath:(NSString *)binaryPath error:(NSError **)error
{
  // It would be better to use lipo(1) or read the Mach-O header.
  id<FBTask> task = [[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/file" arguments:@[binaryPath]]
    startSynchronouslyWithTimeout:30];

  if (task.error) {
    return [[[FBSimulatorError describeFormat:@"Could not obtain archs for binary %@", binaryPath] causedBy:task.error] fail:error];
  }

  NSString *fileOutput = task.stdOut;
  NSArray *matches = [self.fileArchRegex matchesInString:fileOutput options:(NSMatchingOptions)0 range:NSMakeRange(0, fileOutput.length)];

  NSMutableArray *architectures = [NSMutableArray array];
  for (NSTextCheckingResult *result in matches) {
    [architectures addObject:[fileOutput substringWithRange:[result rangeAtIndex:1]]];
  }
  if (architectures.count < 1) {
    return [[[FBSimulatorError describeFormat:@"Arch output does not contain archs %@", fileOutput] causedBy:task.error] fail:error];
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
