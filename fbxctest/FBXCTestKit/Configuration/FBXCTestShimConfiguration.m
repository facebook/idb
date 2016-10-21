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

#import "FBXCTestError.h"
#import "FBXCTestConfiguration.h"

static NSString *const iOSXCTestShimFileName = @"otest-shim-ios.dylib";
static NSString *const MacXCTestShimFileName = @"otest-shim-osx.dylib";
static NSString *const MacQueryShimFileName = @"otest-query-lib-osx.dylib";
static NSString *const ConfirmShimsAreSignedEnv = @"FBXCTEST_CONFIRM_SIGNED_SHIMS";

@implementation FBXCTestShimConfiguration

#pragma mark Initializers

+ (NSDictionary<NSString *, NSNumber *> *)shimFilenamesToCodesigningRequired
{
  NSMutableDictionary<NSString *, NSNumber *> *shims = [NSMutableDictionary dictionaryWithDictionary:@{
    iOSXCTestShimFileName : @NO,
    MacXCTestShimFileName : @NO,
    MacQueryShimFileName : @NO,
  }];
  if (NSProcessInfo.processInfo.environment[ConfirmShimsAreSignedEnv].boolValue && FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    shims[iOSXCTestShimFileName] = @YES;
  }
  return [shims copy];
}

+ (nullable NSString *)findShimDirectoryWithError:(NSError **)error
{
  // If an environment variable is provided, use it
  NSString *environmentDefinedDirectory = NSProcessInfo.processInfo.environment[@"TEST_SHIMS_DIRECTORY"];
  if (environmentDefinedDirectory) {
    return [self confirmExistenceOfRequiredShimsInDirectory:environmentDefinedDirectory error:error];
  }

  // Otherwise, expect it to be relative to the location of the current executable.
  NSString *libPath = [FBXCTestConfiguration.fbxctestInstallationRoot stringByAppendingPathComponent:@"lib"];
  return [self confirmExistenceOfRequiredShimsInDirectory:libPath error:error];
}

+ (nullable NSString *)confirmExistenceOfRequiredShimsInDirectory:(NSString *)directory error:(NSError **)error
{
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[FBXCTestError
      describeFormat:@"A shim directory was expected at '%@', but it was not there", directory]
      fail:error];
  }

  NSDictionary<NSString *, NSNumber *> *shims = self.shimFilenamesToCodesigningRequired;

  id<FBCodesignProvider> codesign = FBCodesignProvider.codeSignCommandWithAdHocIdentity;
  for (NSString *filename in shims) {
    NSString *shimPath = [directory stringByAppendingPathComponent:iOSXCTestShimFileName];
    if (![NSFileManager.defaultManager fileExistsAtPath:shimPath]) {
      return [[FBXCTestError
        describeFormat:@"The iOS xctest Simulator Shim was expected at the location '%@', but it was not there", shimPath]
        fail:error];
    }
    if (!shims[filename].boolValue) {
      continue;
    }
    NSError *innerError = nil;
    if (![codesign cdHashForBundleAtPath:shimPath error:&innerError]) {
      return [[[FBXCTestError
        describeFormat:@"Shim at path %@ was required to be signed, but it was not", shimPath]
        causedBy:innerError]
        fail:error];
    }
  }
  return directory;
}

+ (nullable instancetype)defaultShimConfigurationWithError:(NSError **)error
{
  NSError *innerError = nil;
  NSString *shimDirectory = [self findShimDirectoryWithError:&innerError];
  if (!shimDirectory) {
    return [FBXCTestError failWithError:innerError errorOut:error];
  }
  return [self shimConfigurationWithDirectory:shimDirectory error:error];
}

+ (nullable instancetype)shimConfigurationWithDirectory:(NSString *)directory error:(NSError **)error
{
  NSError *innerError = nil;
  NSString *shimDirectory = [self confirmExistenceOfRequiredShimsInDirectory:directory error:error];
  if (!shimDirectory) {
    return [FBXCTestError failWithError:innerError errorOut:error];
  }
  NSString *iOSTestShimPath = [shimDirectory stringByAppendingPathComponent:iOSXCTestShimFileName];
  NSString *macTestShimPath = [shimDirectory stringByAppendingPathComponent:MacXCTestShimFileName];
  NSString *macQueryShimPath = [shimDirectory stringByAppendingPathComponent:MacQueryShimFileName];

  return [[self alloc] initWithiOSSimulatorTestShim:iOSTestShimPath macTestShim:macTestShimPath macQueryShim:macQueryShimPath];
}

- (instancetype)initWithiOSSimulatorTestShim:(NSString *)iosSimulatorTestShim macTestShim:(NSString *)macTestShim macQueryShim:(NSString *)macQueryShim
{
  NSParameterAssert(iOSXCTestShimFileName);
  NSParameterAssert(macTestShim);
  NSParameterAssert(macQueryShim);

  self = [super init];
  if (!self) {
    return nil;
  }

  _iOSSimulatorOtestShimPath = iosSimulatorTestShim;
  _macOtestShimPath = macTestShim;
  _macOtestQueryPath = macQueryShim;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

- (id)jsonSerializableRepresentation
{
  return @{
    @"ios_simulator_test_shim" : self.iOSSimulatorOtestShimPath,
    @"mac_test_shim" : self.macOtestShimPath,
    @"mac_query_shim" : self.macOtestQueryPath,
  };
}

@end
