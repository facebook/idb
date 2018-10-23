/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessOutputConfiguration.h"

#import <FBControlCore/FBControlCore.h>

static NSString *const KeyBundleID = @"bundle_id";
static NSString *const KeyBundleName = @"bundle_name";
static NSString *const KeyWaitForDebugger = @"wait_for_debugger";
static NSString *const KeyLaunchMode = @"launch_mode";

@implementation FBApplicationLaunchConfiguration

+ (instancetype)configurationWithApplication:(FBApplicationBundle *)application arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output
{
  return [self configurationWithBundleID:application.bundleID bundleName:application.name arguments:arguments environment:environment output:output launchMode:FBApplicationLaunchModeFailIfRunning];
}

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output
{
  return [[self alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment waitForDebugger:waitForDebugger output:output launchMode:FBApplicationLaunchModeFailIfRunning];
}

+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(nullable NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output launchMode:(FBApplicationLaunchMode)launchMode
{
  if (!bundleID || !arguments || !environment) {
    return nil;
  }

  return [[self alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment waitForDebugger:NO output:output launchMode:launchMode];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *bundleID = json[KeyBundleID];
  if (![bundleID isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a bundle_id", bundleID] fail:error];
  }
  NSString *bundleName = json[KeyBundleName];
  if (bundleName && ![bundleName isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a bundle_name", bundleName] fail:error];
  }
  NSNumber *waitForDebugger = json[KeyWaitForDebugger] ?: @NO;
  if (![waitForDebugger isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a boolean signalizing whether to wait for debugger", waitForDebugger] fail:error];
  }
  NSNumber *launchMode = json[KeyLaunchMode] ?: @NO;
  if (![launchMode isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an enum signalizing the launch mode", launchMode] fail:error];
  }
  NSArray<NSString *> *arguments = nil;
  NSDictionary<NSString *, NSString *> *environment = nil;
  FBProcessOutputConfiguration *output = nil;
  if (![FBProcessLaunchConfiguration fromJSON:json extractArguments:&arguments environment:&environment output:&output error:error]) {
    return nil;
  }
  if (waitForDebugger.boolValue && launchMode.intValue == FBApplicationLaunchModeForegroundIfRunning) {
    *error = [FBControlCoreError errorForDescription:@"Can't wait for a debugger when launchMode = FBApplicationLaunchModeForegroundIfRunning"];
    return nil;
  }
  return [[FBApplicationLaunchConfiguration alloc] initWithBundleID:bundleID bundleName:bundleName arguments:arguments environment:environment waitForDebugger:waitForDebugger.boolValue output:output launchMode:(FBApplicationLaunchMode)launchMode.intValue];
}

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(nullable NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output launchMode:(FBApplicationLaunchMode)launchMode
{
  self = [super initWithArguments:arguments environment:environment output:output];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;
  _bundleName = bundleName;
  _waitForDebugger = waitForDebugger;
  _launchMode = launchMode;

  return self;
}

- (instancetype)withWaitForDebugger:(NSError * _Nullable __autoreleasing *)error
{
  if (self.launchMode == FBApplicationLaunchModeForegroundIfRunning) {
    *error = [FBControlCoreError errorForDescription:@"Can't wait for a debugger when launchMode = FBApplicationLaunchModeForegroundIfRunning"];
  }
  return [[FBApplicationLaunchConfiguration alloc]
          initWithBundleID:self.bundleID
          bundleName:self.bundleName
          arguments:self.arguments
          environment:self.environment
          waitForDebugger:YES
          output:self.output
          launchMode:self.launchMode];
}

- (instancetype)withOutput:(FBProcessOutputConfiguration *)output
{
    return [[FBApplicationLaunchConfiguration alloc]
      initWithBundleID:self.bundleID
      bundleName:self.bundleName
      arguments:self.arguments
      environment:self.environment
      waitForDebugger:self.waitForDebugger
      output:output
      launchMode:self.launchMode];
}

#pragma mark Abstract Methods

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
          @"%@ | Arguments %@ | Environment %@ | WaitForDebugger %@ | LaunchMode %lu | Output %@",
          self.shortDescription,
          [FBCollectionInformation oneLineDescriptionFromArray:self.arguments],
          [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
          self.waitForDebugger != 0 ? @"YES" : @"NO",
          (unsigned long)self.launchMode,
    self.output
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"App Launch %@ (%@)", self.bundleID, self.bundleName];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithBundleID:self.bundleID
    bundleName:self.bundleName
    arguments:self.arguments
    environment:self.environment
    waitForDebugger:self.waitForDebugger
    output:self.output
    launchMode:self.launchMode];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [super hash] ^ self.bundleID.hash ^ self.bundleName.hash + (self.waitForDebugger ? 1231 : 1237);
}

- (BOOL)isEqual:(FBApplicationLaunchConfiguration *)object
{
  return [super isEqual:object] &&
         [self.bundleID isEqualToString:object.bundleID] &&
         (self.bundleName == object.bundleName || [self.bundleName isEqual:object.bundleName]) &&
          self.waitForDebugger == self.waitForDebugger &&
          self.launchMode == object.launchMode;

}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *representation = [[super jsonSerializableRepresentation] mutableCopy];
  representation[KeyBundleID] = self.bundleID;
  representation[KeyBundleName] = self.bundleName;
  representation[KeyWaitForDebugger] = @(self.waitForDebugger);
  representation[KeyLaunchMode] = @(self.launchMode);
  return [representation mutableCopy];
}

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeApplicationLaunch;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  return [[target launchApplication:self] mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
