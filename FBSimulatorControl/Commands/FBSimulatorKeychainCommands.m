/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorKeychainCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLaunchCtlCommands.h"

static NSString *const SecuritydServiceName = @"com.apple.securityd";
static NSTimeInterval const kSecuritydServiceStartupShutdownTimeout = 10.f;

@interface FBSimulatorKeychainCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorKeychainCommands

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
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

#pragma mark Public

- (FBFuture<NSNull *> *)clearKeychain
{
  FBFuture<NSNull *> *stopServiceFuture = FBFuture.empty;
  if (self.simulator.state == FBiOSTargetStateBooted) {
    stopServiceFuture = [[[self.simulator stopServiceWithName:SecuritydServiceName] mapReplace:NSNull.null]
      timeout:kSecuritydServiceStartupShutdownTimeout waitingFor:@"%@ service to stop", SecuritydServiceName];
  }
  return [stopServiceFuture
    onQueue:self.simulator.workQueue fmap:^ FBFuture<NSNull *> * (id _) {
      NSError *error = nil;
      if (![self removeKeychainContentsWithLogger:self.simulator.logger error:&error]) {
        return [FBFuture futureWithError:error];
      }
      if (self.simulator.state == FBiOSTargetStateBooted) {
        return [[[self.simulator startServiceWithName:SecuritydServiceName] mapReplace:NSNull.null]
          timeout:kSecuritydServiceStartupShutdownTimeout waitingFor:@"%@ service to restart", SecuritydServiceName];
      }
      return FBFuture.empty;
    }];
}

#pragma mark Private

+ (NSSet<NSString *> *)keychainPathsToIgnore
{
  static dispatch_once_t onceToken;
  static NSSet<NSString *> *paths;
  dispatch_once(&onceToken, ^{
    paths = [NSSet setWithArray:@[@"TrustStore.sqlite3"]];
  });
  return paths;
}

- (BOOL)removeKeychainContentsWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSString *keychainDirectory = [[self.simulator.dataDirectory
    stringByAppendingPathComponent:@"Library"]
    stringByAppendingPathComponent:@"Keychains"];

  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:keychainDirectory isDirectory:&isDirectory]) {
    [self.simulator.logger.info logFormat:@"The keychain directory does not exist at '%@'", keychainDirectory];
    return YES;
  }
  if (!isDirectory) {
    return [[FBSimulatorError
      describeFormat:@"Keychain path %@ is not a directory", keychainDirectory]
      failBool:error];
  }

  NSError *innerError = nil;
  NSArray<NSString *> *paths = [NSFileManager.defaultManager contentsOfDirectoryAtPath:keychainDirectory error:&innerError];
  if (!paths) {
    return [[FBSimulatorError
      describeFormat:@"Could not list the contents of the keychain directory %@", keychainDirectory]
      failBool:error];
  }
  for (NSString *path in paths) {
    NSString *fullPath = [keychainDirectory stringByAppendingPathComponent:path];
    if ([FBSimulatorKeychainCommands.keychainPathsToIgnore containsObject:fullPath.lastPathComponent]) {
      [logger logFormat:@"Not removing keychain at path %@", fullPath];
      continue;
    }
    [logger logFormat:@"Removing keychain at path %@", fullPath];
    if (![NSFileManager.defaultManager removeItemAtPath:fullPath error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to delete keychain at path %@", fullPath]
        causedBy:innerError]
        failBool:error];
    }
  }

  return YES;
}

@end
