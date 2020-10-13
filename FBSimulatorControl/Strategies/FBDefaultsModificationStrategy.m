/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDefaultsModificationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtlCommands.h"
#import "FBAgentLaunchStrategy.h"

@interface FBDefaultsModificationStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBDefaultsModificationStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

- (FBBinaryDescriptor *)defaultsBinary
{
  NSString *path = [[[self.simulator.device.runtime.root
    stringByAppendingPathComponent:@"usr"]
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"defaults"];
  NSError *error = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:&error];
  NSAssert(binary, @"Could not locate defaults at expected location '%@', error %@", path, error);
  return binary;
}

- (FBFuture<NSNull *> *)modifyDefaultsInDomainOrPath:(NSString *)domainOrPath defaults:(NSDictionary<NSString *, id> *)defaults
{
  NSError *innerError = nil;
  NSString *file = [self.simulator.auxillaryDirectory stringByAppendingPathComponent:@"temporary.plist"];
  if (![NSFileManager.defaultManager createDirectoryAtPath:[file stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not create intermediate directories for temporary plist %@", file]
      causedBy:innerError]
      failFuture];
  }
  if (![defaults writeToFile:file atomically:YES]) {
    return [[FBSimulatorError
      describeFormat:@"Failed to write out defaults to temporary file %@", file]
      failFuture];
  }

  // Build the arguments
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:@"import"];
  if (domainOrPath) {
    [arguments addObject:domainOrPath];
  }
  [arguments addObject:file];

  // Make the Launch Config
  FBAgentLaunchConfiguration *configuration = [FBAgentLaunchConfiguration
    configurationWithBinary:self.defaultsBinary
    arguments:arguments
    environment:@{}
    output:FBProcessOutputConfiguration.outputToDevNull
    mode:FBAgentLaunchModeDefault];

  // Run the write, fail if the write fails.
  return [[[FBAgentLaunchStrategy strategyWithSimulator:self.simulator]
    launchAndNotifyOfCompletion:configuration]
    mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)amendRelativeToPath:(NSString *)relativePath defaults:(NSDictionary<NSString *, id> *)defaults managingService:(NSString *)serviceName
{
  FBSimulator *simulator = self.simulator;
  FBiOSTargetState state = simulator.state;
  if (state != FBiOSTargetStateBooted && state != FBiOSTargetStateShutdown) {
    return [[FBSimulatorError
      describeFormat:@"Cannot amend a plist when the Simulator state is %@, should be %@ or %@", FBiOSTargetStateStringFromState(state), FBiOSTargetStateStringShutdown, FBiOSTargetStateStringBooted]
      failFuture];
  }

  // Stop the service, if booted.
  FBFuture<NSNull *> *stopFuture = state == FBiOSTargetStateBooted
    ? [[simulator stopServiceWithName:serviceName] mapReplace:NSNull.null]
    : FBFuture.empty;

  // The path to amend.
  NSString *fullPath = [self.simulator.dataDirectory stringByAppendingPathComponent:relativePath];

  return  [[stopFuture
    onQueue:self.simulator.workQueue fmap:^FBFuture *(NSNull *_) {
      return [self modifyDefaultsInDomainOrPath:fullPath defaults:defaults];
    }]
    onQueue:self.simulator.workQueue fmap:^FBFuture<NSNull *> *(NSNull *_) {
      // Re-start the Service if booted.
      return state == FBiOSTargetStateBooted
        ? [[simulator startServiceWithName:serviceName] mapReplace:NSNull.null]
        : FBFuture.empty;
    }];
}

@end

@implementation FBLocalizationDefaultsModificationStrategy

- (FBFuture<NSNull *> *)overrideLocalization:(FBLocalizationOverride *)localizationOverride
{
  return [self modifyDefaultsInDomainOrPath:nil defaults:localizationOverride.defaultsDictionary];
}

@end

@implementation FBLocationServicesModificationStrategy

- (FBFuture<NSNull *> *)approveLocationServicesForBundleIDs:(NSArray<NSString *> *)bundleIDs
{
  NSParameterAssert(bundleIDs);

  NSMutableDictionary<NSString *, id> *defaults = [NSMutableDictionary dictionary];
  for (NSString *bundleID in bundleIDs) {
    defaults[bundleID] = @{
      @"Whitelisted": @NO,
      @"BundleId": bundleID,
      @"SupportedAuthorizationMask" : @3,
      @"Authorization" : @2,
      @"Authorized": @YES,
      @"Executable": @"",
      @"Registered": @"",
    };
  }

  return [self
    amendRelativeToPath:@"Library/Caches/locationd/clients.plist"
    defaults:[defaults copy]
    managingService:@"locationd"];
}

@end

@implementation FBWatchdogOverrideModificationStrategy

- (FBFuture<NSNull *> *)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs timeout:(NSTimeInterval)timeout
{
  NSParameterAssert(bundleIDs);
  NSParameterAssert(timeout);

  NSMutableDictionary<NSString *, NSNumber *> *exceptions = [NSMutableDictionary dictionary];
  for (NSString *bundleID in bundleIDs) {
    exceptions[bundleID] = @(timeout);
  }
  NSDictionary *defaults = @{@"FBLaunchWatchdogExceptions" : [exceptions copy]};
  return [self
    amendRelativeToPath:@"Library/Preferences/com.apple.springboard.plist"
    defaults:defaults
    managingService:@"com.apple.SpringBoard"];
}

@end

@implementation FBKeyboardSettingsModificationStrategy

- (FBFuture<NSNull *> *)setupKeyboard
{
  NSDictionary<NSString *, NSString *> *defaults = @{
    @"KeyboardCapsLock" : @"0",
    @"KeyboardAutocapitalization" : @"0",
    @"KeyboardAutocorrection" : @"0",
  };
  return [self modifyDefaultsInDomainOrPath:@"com.apple.Preferences" defaults:defaults];
}

@end
