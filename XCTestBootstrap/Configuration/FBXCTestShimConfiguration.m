/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestShimConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"

NSString *const FBXCTestShimDirectoryEnvironmentOverride = @"TEST_SHIMS_DIRECTORY";

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
    KeySimulatorTestShim: @(FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid),
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
    return [[[FBControlCoreError
      describeFormat:@"No shim located at expected location of %@", shimPath]
      noLogging]
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
    onQueue:queue resolve:^ FBFuture<NSString *> * {
      NSMutableArray<NSString *> *searchPaths = NSMutableArray.array;
      NSString *environmentDefinedDirectory = NSProcessInfo.processInfo.environment[FBXCTestShimDirectoryEnvironmentOverride];
      if (environmentDefinedDirectory) {
        [searchPaths addObject:environmentDefinedDirectory];
      }
      [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"lib"]];
      [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"bin"]];
      [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"idb"]];
      [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"idb/bin"]];
      [searchPaths addObject:[NSBundle bundleForClass:self].resourcePath];

      NSMutableArray<FBFuture<NSString *> *> *futures = NSMutableArray.array;
      for (NSString *path in searchPaths) {
        [futures addObject:[[self confirmExistenceOfRequiredShimsInDirectory:path] fallback:@""]];
      }
      return [[FBFuture
        futureWithFutures:futures]
        onQueue:queue fmap:^(NSArray<NSString *> *paths) {
          for (NSString *path in paths) {
            if (path.length == 0) {
              continue;
            }
            return [FBFuture futureWithResult:path];
          }
          return [[FBControlCoreError
            describeFormat:@"Could not find shims in any of the expected directories %@", [FBCollectionInformation oneLineDescriptionFromArray:searchPaths]]
            failFuture];
        }];
    }];
}

+ (FBFuture<NSString *> *)confirmExistenceOfRequiredShimsInDirectory:(NSString *)directory
{
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[[FBXCTestError
      describeFormat:@"A shim directory was searched for at '%@', but it was not there", directory]
      noLogging]
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
