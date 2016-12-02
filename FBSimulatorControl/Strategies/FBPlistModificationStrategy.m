/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBPlistModificationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBAgentLaunchStrategy.h"

@interface FBPlistModificationStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBPlistModificationStrategy

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

- (BOOL)amendRelativeToPath:(NSString *)relativePath error:(NSError **)error amendWithBlock:( void(^)(NSMutableDictionary<NSString *, id> *) )block
{
  FBSimulator *simulator = self.simulator;
  NSString *simulatorRoot = simulator.device.dataPath;
  NSString *path = [simulatorRoot stringByAppendingPathComponent:relativePath];

  NSError *innerError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not create intermediate directories for plist modification at %@", path]
      inSimulator:simulator]
      causedBy:innerError]
      failBool:error];
  }
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
  block(dictionary);

  if (![dictionary writeToFile:path atomically:YES]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to write plist at path %@", path]
      inSimulator:simulator]
      failBool:error];
  }
  return YES;
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

- (BOOL)modifyDefaultsInDomain:(NSString *)domain defaults:(NSDictionary<NSString *, id> *)defaults error:(NSError **)error
{
  NSError *innerError = nil;
  NSString *file = [self.simulator.auxillaryDirectory stringByAppendingPathComponent:@"temporary.plist"];
  if (![NSFileManager.defaultManager createDirectoryAtPath:[file stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not create intermediate directories for temporary plist %@", file]
      causedBy:innerError]
      failBool:error];
  }
  if (![defaults writeToFile:file atomically:YES]) {
    return [[FBSimulatorError
      describeFormat:@"Failed to write out defaults to temporary file %@", file]
      failBool:error];
  }

  // Build the arguments
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:@"import"];
  if (domain) {
    [arguments addObject:domain];
  }
  [arguments addObject:file];

  // Make the Launch Config
  FBAgentLaunchConfiguration *configuration = [FBAgentLaunchConfiguration
    configurationWithBinary:self.defaultsBinary
    arguments:arguments
    environment:@{}
    options:0];

  // Run the write, fail if the write fails.
  FBAgentLaunchStrategy *strategy = [FBAgentLaunchStrategy withSimulator:self.simulator];
  if (![strategy launchConsumingStdout:configuration error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to write defaults for %@", domain ?: @"GLOBAL"]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

- (BOOL)amendRelativeToPath:(NSString *)relativePath managingService:(NSString *)serviceName error:(NSError **)error amendWithBlock:( void(^)(NSMutableDictionary<NSString *, id> *) )block
{
  FBSimulator *simulator = self.simulator;
  FBSimulatorState state = simulator.state;
  if (state != FBSimulatorStateBooted && state != FBSimulatorStateShutdown) {
    return [[FBSimulatorError
      describeFormat:@"Cannot amend a plist when the Simulator state is %@, should be %@ or %@", [FBSimulator stateStringFromSimulatorState:state], [FBSimulator stateStringFromSimulatorState:FBSimulatorStateShutdown], [FBSimulator stateStringFromSimulatorState:FBSimulatorStateBooted]]
      failBool:error];
  }
  // Stop the service, if booted.
  if (state == FBSimulatorStateBooted) {
    if (![simulator.launchctl stopServiceWithName:serviceName error:error]) {
      return NO;
    }
  }
  // Perform the amend.
  if (![self amendRelativeToPath:relativePath error:error amendWithBlock:block]) {
    return NO;
  }
  // Re-start the Service if booted.
  if (state == FBSimulatorStateBooted) {
    if (![simulator.launchctl startServiceWithName:serviceName error:error]) {
      return NO;
    }
  }
  return YES;
}

@end

@implementation FBLocalizationDefaultsModificationStrategy

- (BOOL)overideLocalization:(FBLocalizationOverride *)localizationOverride error:(NSError **)error
{
  return [self modifyDefaultsInDomain:nil defaults:localizationOverride.defaultsDictionary error:error];
}

@end

@implementation FBLocationServicesModificationStrategy

- (BOOL)overideLocalizations:(NSArray<NSString *> *)bundleIDs error:(NSError **)error
{
  NSParameterAssert(bundleIDs);

  return [self
    amendRelativeToPath:@"Library/Caches/locationd/clients.plist"
    managingService:@"locationd"
    error:error
    amendWithBlock:^(NSMutableDictionary *dictionary) {
      for (NSString *bundleID in bundleIDs) {
        dictionary[bundleID] = @{
          @"Whitelisted": @NO,
          @"BundleId": bundleID,
          @"SupportedAuthorizationMask" : @3,
          @"Authorization" : @2,
          @"Authorized": @YES,
          @"Executable": @"",
          @"Registered": @"",
        };
      }
    }];
}

@end

@implementation FBWatchdogOverrideModificationStrategy

- (BOOL)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  NSParameterAssert(bundleIDs);
  NSParameterAssert(timeout);

  NSMutableDictionary<NSString *, NSNumber *> *exceptions = [NSMutableDictionary dictionary];
  for (NSString *bundleID in bundleIDs) {
    exceptions[bundleID] = @(timeout);
  }
  NSDictionary *defaults = @{@"FBLaunchWatchdogExceptions" : [exceptions copy]};
  return [self modifyDefaultsInDomain:@"com.apple.springboard" defaults:defaults error:error];
}

@end

@implementation FBKeyboardSettingsModificationStrategy

- (BOOL)setupKeyboardWithError:(NSError **)error
{
  NSDictionary<NSString *, NSString *> *defaults = @{
    @"KeyboardCapsLock" : @"0",
    @"KeyboardAutocapitalization" : @"0",
    @"KeyboardAutocorrection" : @"0",
  };
  return [self modifyDefaultsInDomain:@"com.apple.Preferences" defaults:defaults error:error];
}

@end
