/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplication.h"

#import "FBSimulatorError.h"

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

#pragma mark - FBJSONDeserializable

+ (FBSimulatorBinary *)inflateFromJSON:(id)json error:(NSError **)error
{
    NSString *path = json[@"path"];
    if (![path isKindOfClass:NSString.class]) {
        return [[FBSimulatorError describeFormat:@"%@ is not a valid binary path", path] fail:error];
    }
    NSError *innerError = nil;
    FBSimulatorBinary *binary = [FBSimulatorBinary binaryWithPath:path error:&innerError];
    if (!binary) {
        return [[[FBSimulatorError
                  describeFormat:@"Could not create binary from path %@", path]
                 causedBy:innerError]
                fail:error];
    }
    return binary;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name: %@ | Path: %@ | Architectures: %@",
    self.name,
    self.path,
    [FBCollectionInformation oneLineDescriptionFromArray:self.architectures.allObjects]
  ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"name" : self.name,
    @"path" : self.path,
    @"architectures" : self.architectures.allObjects
  };
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

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self shortDescription];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Name: %@ | ID: %@",
    self.name,
    self.bundleID
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Path: %@ | Binary (%@)",
    self.shortDescription,
    self.path,
    self.binary
  ];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"name" : self.name,
    @"bundle_id" : self.bundleID,
    @"path" : self.path,
    @"binary" : self.binary.jsonSerializableRepresentation
  };
}

@end

@implementation FBSimulatorApplication (Helpers)

+ (instancetype)applicationWithPath:(NSString *)path error:(NSError **)error;
{
  NSMutableDictionary *applicationCache = self.applicationCache;
  FBSimulatorApplication *application = applicationCache[path];
  if (application) {
    return application;
  }

  NSError *innerError = nil;
  application = [FBSimulatorApplication createApplicationWithPath:path error:&innerError];
  if (!application) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  applicationCache[path] = application;
  return application;
}

+ (instancetype)systemApplicationNamed:(NSString *)appName error:(NSError **)error
{
  return [self applicationWithPath:[self pathForSystemApplicationNamed:appName] error:error];
}

+ (instancetype)xcodeSimulator;
{
  NSError *error = nil;
  FBSimulatorApplication *application = [self applicationWithPath:self.pathForSimulatorApplication error:&error];
  NSAssert(application, @"Expected to be able to build an Application, got an error %@", application);
  return application;
}

#pragma mark Private

+ (NSString *)pathForSimulatorApplication
{
  NSString *simulatorBinaryName = [FBControlCoreGlobalConfiguration.sdkVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]]
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

@implementation FBSimulatorBinary (Helpers)

+ (instancetype)binaryWithPath:(NSString *)binaryPath error:(NSError **)error;
{
  NSError *innerError = nil;
  if (![NSFileManager.defaultManager fileExistsAtPath:binaryPath]) {
    return [[FBSimulatorError
      describeFormat:@"Binary does not exist at path %@", binaryPath]
      fail:error];
  }

  NSSet *archs = [FBBinaryParser architecturesForBinaryAtPath:binaryPath error:&innerError];
  if (archs.count < 1) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  return [[FBSimulatorBinary alloc]
    initWithName:[self binaryNameForBinaryPath:binaryPath]
    path:binaryPath
    architectures:archs];
}

+ (instancetype)launchCtl
{
  NSError *error = nil;
  FBSimulatorBinary *binary = [FBSimulatorBinary binaryWithPath:self.pathForiPhoneLaunchCtl error:&error];
  NSAssert(binary, @"Failed to construct launchctl binary with error %@", error);
  return binary;
}

#pragma mark Private

+ (NSString *)pathForiPhoneLaunchCtl
{
  return [FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"/Platforms/WatchSimulator.platform/Developer/SDKs/WatchSimulator.sdk/bin/launchctl"];
}

+ (NSString *)binaryNameForBinaryPath:(NSString *)binaryPath
{
  return binaryPath.lastPathComponent;
}

@end
