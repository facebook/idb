/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

- (NSString *)defaultsBinary
{
  NSString *path = [[[self.simulator.device.runtime.root
    stringByAppendingPathComponent:@"usr"]
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"defaults"];
  NSError *error = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:&error];
  NSAssert(binary, @"Could not locate defaults at expected location '%@', error %@", path, error);
  return binary.path;
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

  return [[self performDefaultsCommandWithArguments:arguments] mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)setDefaultInDomain:(NSString *)domain key:(NSString *)key value:(NSString *)value type:(NSString *)type
{
  return [[self
    performDefaultsCommandWithArguments:@[
      @"write",
      domain,
      key,
      [NSString stringWithFormat:@"-%@", type ? type : @"string"],
      value,
    ]]
    mapReplace:NSNull.null];
}

- (FBFuture<NSString *> *)getDefaultInDomain:(NSString *)domain key:(NSString *)key
{
  return [self
    performDefaultsCommandWithArguments:@[
      @"read",
      domain,
      key,
    ]];
}

- (FBFuture<NSString *> *)performDefaultsCommandWithArguments:(NSArray<NSString *> *)arguments
{
  // Make the Launch Config
  FBProcessSpawnConfiguration *configuration = [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:self.defaultsBinary
    arguments:arguments
    environment:@{}
    io:FBProcessIO.outputToDevNull
    mode:FBProcessSpawnModeDefault];

  // Run the defaults command.
  return [[FBProcessSpawnCommandHelpers
    launchConsumingStdout:configuration withCommands:self.simulator]
    onQueue:self.simulator.asyncQueue map:^(NSString *output) {
      return [output stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    }];
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

@implementation FBPreferenceModificationStrategy

static NSString *const AppleGlobalDomain = @"Apple Global Domain";

- (FBFuture<NSNull *> *)setPreference:(NSString *)name value:(NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain
{
  if (domain == nil) {
    domain = AppleGlobalDomain;
  }
  return [self setDefaultInDomain:domain key:name value:value type:type];
}

- (FBFuture<NSString *> *)getCurrentPreference:(NSString *)name domain:(nullable NSString *)domain
{
  if (domain == nil) {
    domain = AppleGlobalDomain;
  }
  return [self getDefaultInDomain:domain key:name];
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

- (FBFuture<NSNull *> *)revokeLocationServicesForBundleIDs:(NSArray<NSString *> *)bundleIDs
{
  NSParameterAssert(bundleIDs);

    FBSimulator *simulator = self.simulator;
    FBiOSTargetState state = simulator.state;
    if (state != FBiOSTargetStateBooted && state != FBiOSTargetStateShutdown) {
      return [[FBSimulatorError
        describeFormat:@"Cannot modify a plist when the Simulator state is %@, should be %@ or %@", FBiOSTargetStateStringFromState(state), FBiOSTargetStateStringShutdown, FBiOSTargetStateStringBooted]
        failFuture];
    }

    NSString *serviceName = @"locationd";

    // Stop the service, if booted.
    FBFuture<NSNull *> *stopFuture = state == FBiOSTargetStateBooted
      ? [[simulator stopServiceWithName:serviceName] mapReplace:NSNull.null]
      : FBFuture.empty;

    NSString *path = [self.simulator.dataDirectory
                      stringByAppendingPathComponent:@"Library/Caches/locationd/clients.plist"];
    NSMutableArray<FBFuture<NSString *> *> *futures = [NSMutableArray array];
    for (NSString *bundleID in bundleIDs) {
      [futures addObject:
       [self
        performDefaultsCommandWithArguments:@[
          @"delete",
          path,
          bundleID,
        ]]];
    }

    return [[stopFuture
      onQueue:self.simulator.workQueue fmap:^FBFuture *(NSNull *_) {
        return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
      }]
      onQueue:self.simulator.workQueue fmap:^FBFuture<NSNull *> *(NSNull *_) {
        // Re-start the Service if booted.
        return state == FBiOSTargetStateBooted
          ? [[simulator startServiceWithName:serviceName] mapReplace:NSNull.null]
          : FBFuture.empty;
      }];
}

@end
