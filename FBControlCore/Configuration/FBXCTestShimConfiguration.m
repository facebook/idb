/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestShimConfiguration.h"

#import <FBControlCore/FBControlCore.h>

NSString *const FBXCTestShimDirectoryEnvironmentOverride = @"TEST_SHIMS_DIRECTORY";

static NSString *const KeySimulatorTestShim = @"ios_simulator_test_shim";
static NSString *const KeyMacTestShim = @"mac_test_shim";

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
  };
}

+ (NSDictionary<NSString *, NSNumber *> *)canonicalShimNameToCodesigningRequired
{
  return @{
    KeySimulatorTestShim: @(FBControlCoreGlobalConfiguration.confirmCodesignaturesAreValid),
    KeyMacTestShim: @NO,
  };
}

+ (FBFuture<NSString *> *)pathForCanonicallyNamedShim:(NSString *)canonicalName inDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger
{
  NSString *filename = self.canonicalShimNameToShimFilenames[canonicalName];
  FBCodesignProvider *codesign = [FBCodesignProvider codeSignCommandWithAdHocIdentityWithLogger:nil];
  BOOL signingRequired = self.canonicalShimNameToCodesigningRequired[canonicalName].boolValue;

  NSString *shimPath = [directory stringByAppendingPathComponent:filename];
  if (![NSFileManager.defaultManager fileExistsAtPath:shimPath]) {
    return [[FBControlCoreError
      describeFormat:@"No shim located at expected location of %@", shimPath]
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

+ (FBFuture<NSString *> *)findShimDirectoryOnQueue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [FBFuture
    onQueue:queue resolve:^ FBFuture<NSString *> * {
      NSMutableArray<NSString *> *searchPaths = NSMutableArray.array;
      NSString *environmentDefinedDirectory = NSProcessInfo.processInfo.environment[FBXCTestShimDirectoryEnvironmentOverride];
      if (environmentDefinedDirectory) {
        [searchPaths addObject:environmentDefinedDirectory];
      } else {
        [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"lib"]];
        [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"bin"]];
        [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"idb"]];
        [searchPaths addObject:[self.fbxctestInstallationRoot stringByAppendingPathComponent:@"idb/bin"]];
        [searchPaths addObject:[NSBundle bundleForClass:self].resourcePath];
      }

      NSMutableArray<FBFuture<NSString *> *> *futures = NSMutableArray.array;
      for (NSString *path in searchPaths) {
        [futures addObject:[[self confirmExistenceOfRequiredShimsInDirectory:path logger:logger] fallback:@""]];
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
          NSArray<NSString *> *shimNames = self.canonicalShimNameToShimFilenames.allValues;
          return [[FBControlCoreError
            describeFormat:@"Could not find all shims %@ in any of the expected directories %@", [FBCollectionInformation oneLineDescriptionFromArray:shimNames], [FBCollectionInformation oneLineDescriptionFromArray:searchPaths]]
            failFuture];
        }];
    }];
}

+ (FBFuture<NSString *> *)confirmExistenceOfRequiredShimsInDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger
{
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[FBControlCoreError
      describeFormat:@"A shim directory was searched for at '%@', but it was not there", directory]
      failFuture];
  }
  NSMutableArray<FBFuture<NSString *> *> *futures = [NSMutableArray array];
  for (NSString *canonicalName in self.canonicalShimNameToShimFilenames.allKeys) {
    [futures addObject:[self pathForCanonicallyNamedShim:canonicalName inDirectory:directory logger:logger]];
  }
  return [[FBFuture
    futureWithFutures:futures]
    mapReplace:directory];
}

+ (FBFuture<FBXCTestShimConfiguration *> *)sharedShimConfigurationWithLogger:(id<FBControlCoreLogger>)logger
{
  static dispatch_once_t onceToken;
  static FBFuture<FBXCTestShimConfiguration *> *future;
  dispatch_once(&onceToken, ^{
    future = [self defaultShimConfigurationWithLogger:logger];
  });
  return future;
}

+ (FBFuture<FBXCTestShimConfiguration *> *)defaultShimConfigurationWithLogger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [[self
    findShimDirectoryOnQueue:queue logger:logger]
    onQueue:queue fmap:^(NSString *directory) {
      return [self shimConfigurationWithDirectory:directory logger:logger];
    }];
}

+ (FBFuture<FBXCTestShimConfiguration *> *)shimConfigurationWithDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [[[self
    confirmExistenceOfRequiredShimsInDirectory:directory logger:logger]
    onQueue:queue fmap:^(NSString *shimDirectory) {
      return [FBFuture futureWithFutures:@[
        [self pathForCanonicallyNamedShim:KeySimulatorTestShim inDirectory:shimDirectory logger:logger],
        [self pathForCanonicallyNamedShim:KeyMacTestShim inDirectory:shimDirectory logger:logger],
      ]];
    }]
    onQueue:queue map:^(NSArray<NSString *> *shims) {
      return [[self alloc] initWithiOSSimulatorTestShimPath:shims[0] macOSTestShimPath:shims[1]];
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

- (instancetype)initWithiOSSimulatorTestShimPath:(NSString *)iosSimulatorTestShim macOSTestShimPath:(NSString *)macOSTestShimPath
{
  NSParameterAssert(iosSimulatorTestShim);
  NSParameterAssert(macOSTestShimPath);

  self = [super init];
  if (!self) {
    return nil;
  }

  _iOSSimulatorTestShimPath = iosSimulatorTestShim;
  _macOSTestShimPath = macOSTestShimPath;

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
      && [self.macOSTestShimPath isEqualToString:object.macOSTestShimPath];
}

- (NSUInteger)hash
{
  return self.iOSSimulatorTestShimPath.hash ^ self.macOSTestShimPath.hash;
}

@end
