/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestShimConfiguration.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

static NSString *const KeySimulatorTestShim = @"ios_simulator_test_shim";
static NSString *const KeyMacTestShim = @"mac_test_shim";
static NSString *const KeyMacQueryShim = @"mac_query_shim";

static NSString *const shimulatorFileName = @"libShimulator.dylib";
static NSString *const maculatorShimFileName = @"libMaculator.dylib";

@implementation FBXCTestShimConfiguration

#pragma mark Initializers

+ (dispatch_queue_t)createWorkQueue
{
  return dispatch_queue_create("com.facebook.xctestbootstrap.shims", DISPATCH_QUEUE_SERIAL);
}

+ (NSDictionary<NSString *, NSString *> *)canonicalShimNameToShimFilenames
{
  return @{
    KeySimulatorTestShim: shimulatorFileName,
    KeyMacTestShim: maculatorShimFileName,
    KeyMacQueryShim: maculatorShimFileName,
  };
}

+ (NSDictionary<NSString *, NSNumber *> *)canonicalShimNameToCodesigningRequired
{
  return @{
    KeySimulatorTestShim: @(FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid && FBXcodeConfiguration.isXcode8OrGreater),
    KeyMacQueryShim: @NO,
    KeyMacTestShim: @NO,
  };
}

+ (FBFuture<NSString *> *)pathForCanonicallyNamedShim:(NSString *)canonicalName inDirectory:(NSString *)directory
{
  NSString *filename = self.canonicalShimNameToShimFilenames[canonicalName];
  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  BOOL signingRequired = self.canonicalShimNameToCodesigningRequired[canonicalName].boolValue;

  NSString *shimPath = [directory stringByAppendingPathComponent:filename];
  if (![NSFileManager.defaultManager fileExistsAtPath:shimPath]) {
    return [[FBControlCoreError
      describeFormat:@"No shim located at expectect location of %@", shimPath]
      failFuture];
  }
  if (!signingRequired) {
    return [FBFuture futureWithResult:shimPath];
  }
  return [[[codesign
    cdHashForBundleAtPath:shimPath]
    rephraseFailure:@"Shim at path %@ was required to be signed, but it was not", shimPath]
    mapReplace:shimPath];
}

+ (FBFuture<NSString *> *)findShimDirectoryOnQueue:(dispatch_queue_t)queue
{
  return [FBFuture
    onQueue:queue resolve:^ FBFuture<NSString *> *{
      // If an environment variable is provided, use it
      NSString *environmentDefinedDirectory = NSProcessInfo.processInfo.environment[@"TEST_SHIMS_DIRECTORY"];
      if (environmentDefinedDirectory) {
        return [self confirmExistenceOfRequiredShimsInDirectory:environmentDefinedDirectory];
      }

      // Otherwise, expect it to be relative to the location of the current executable.
      NSString *libPath = [self.fbxctestInstallationRoot stringByAppendingPathComponent:@"lib"];
      NSString *bundlePath = [NSBundle bundleForClass:self].resourcePath;
      return [[self
        confirmExistenceOfRequiredShimsInDirectory:libPath]
        onQueue:queue chain:^ FBFuture<NSString *> * (FBFuture<NSString *> *future) {
          if (future.error) {
            return [self confirmExistenceOfRequiredShimsInDirectory:bundlePath];
          }
          return future;
        }];
    }];
}

+ (FBFuture<NSString *> *)confirmExistenceOfRequiredShimsInDirectory:(NSString *)directory
{
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[FBXCTestError
      describeFormat:@"A shim directory was expected at '%@', but it was not there", directory]
      failFuture];
  }
  NSMutableArray<FBFuture<NSString *> *> *futures = [NSMutableArray array];
  for (NSString *canonicalName in self.canonicalShimNameToShimFilenames.allKeys) {
    [futures addObject:[self pathForCanonicallyNamedShim:canonicalName inDirectory:directory]];
  }
  return [[FBFuture
    futureWithFutures:futures]
    mapReplace:directory];
}

+ (FBFuture<FBXCTestShimConfiguration *> *)defaultShimConfiguration
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [[self
    findShimDirectoryOnQueue:queue]
    onQueue:queue fmap:^(NSString *directory) {
      return [self shimConfigurationWithDirectory:directory];
    }];
}

+ (FBFuture<FBXCTestShimConfiguration *> *)shimConfigurationWithDirectory:(NSString *)directory
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [[[self
    confirmExistenceOfRequiredShimsInDirectory:directory]
    onQueue:queue fmap:^(NSString *shimDirectory) {
      return [FBFuture futureWithFutures:@[
        [self pathForCanonicallyNamedShim:KeySimulatorTestShim inDirectory:shimDirectory],
        [self pathForCanonicallyNamedShim:KeyMacTestShim inDirectory:shimDirectory],
        [self pathForCanonicallyNamedShim:KeyMacQueryShim inDirectory:shimDirectory],
      ]];
    }]
    onQueue:queue map:^(NSArray<NSString *> *shims) {
      return [[self alloc] initWithiOSSimulatorTestShimPath:shims[0] macOSTestShimPath:shims[1] macOSQueryShimPath:shims[2]];
    }];
}

+ (NSString *)fbxctestInstallationRoot
{
  NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
  if (!executablePath.isAbsolutePath) {
    executablePath = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingString:executablePath];
  }
  executablePath = [executablePath stringByStandardizingPath];
  NSString *path = [[executablePath
    stringByDeletingLastPathComponent]
    stringByDeletingLastPathComponent];
  return [NSFileManager.defaultManager fileExistsAtPath:path] ? path : nil;
}

- (instancetype)initWithiOSSimulatorTestShimPath:(NSString *)iosSimulatorTestShim macOSTestShimPath:(NSString *)macOSTestShimPath macOSQueryShimPath:(NSString *)macOSQueryShimPath
{
  NSParameterAssert(iosSimulatorTestShim);
  NSParameterAssert(macOSTestShimPath);
  NSParameterAssert(macOSQueryShimPath);

  self = [super init];
  if (!self) {
    return nil;
  }

  _iOSSimulatorTestShimPath = iosSimulatorTestShim;
  _macOSTestShimPath = macOSTestShimPath;
  _macOSQueryShimPath = macOSQueryShimPath;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestShimConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.iOSSimulatorTestShimPath isEqualToString:object.iOSSimulatorTestShimPath]
      && [self.macOSTestShimPath isEqualToString:object.macOSTestShimPath]
      && [self.macOSQueryShimPath isEqualToString:object.macOSQueryShimPath];
}

- (NSUInteger)hash
{
  return self.iOSSimulatorTestShimPath.hash ^ self.macOSTestShimPath.hash ^ self.macOSQueryShimPath.hash;
}

#pragma mark JSON

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, NSString *> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Dictionary<String, String>", json]
      fail:error];
  }
  NSString *simulatorTestShim = json[KeySimulatorTestShim];
  if (![simulatorTestShim isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", simulatorTestShim, KeySimulatorTestShim]
      fail:error];
  }
  NSString *macTestShim = json[KeyMacTestShim];
  if (![macTestShim isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", macTestShim, KeyMacTestShim]
      fail:error];
  }
  NSString *macOSQueryShimPath = json[KeyMacQueryShim];
  if (![macOSQueryShimPath isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", macOSQueryShimPath, KeyMacQueryShim]
      fail:error];
  }
  return [[FBXCTestShimConfiguration alloc] initWithiOSSimulatorTestShimPath:simulatorTestShim macOSTestShimPath:macTestShim macOSQueryShimPath:macOSQueryShimPath];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeySimulatorTestShim: self.iOSSimulatorTestShimPath,
    KeyMacTestShim: self.macOSTestShimPath,
    KeyMacQueryShim: self.macOSQueryShimPath,
  };
}

@end
