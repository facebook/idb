/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDiagnosticInformationCommands.h"

#import "FBDevice.h"
#import "FBAMDServiceConnection.h"
#import "FBManagedConfigClient.h"

static NSString *const DiagnosticsRelayService = @"com.apple.mobile.diagnostics_relay";
static NSString *const SpringboardService = @"com.apple.springboardservices";

@interface FBDeviceDiagnosticInformationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceDiagnosticInformationCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBDeviceDiagnosticInformationCommands Implementation

- (FBFuture<NSDictionary<NSString *, id> *> *)fetchDiagnosticInformation
{
  return [[FBFuture
    futureWithFutures:@[
      [self fetchInformationFromDiagnosticsRelay],
      [self fetchInformationFromSpringboard],
      [self fetchInformationFromMobileConfiguration],
    ]]
    onQueue:self.device.asyncQueue map:^(NSArray<id> *results) {
      return @{
        DiagnosticsRelayService: results[0],
        SpringboardService: results[1],
        FBManagedConfigService: results[2],
      };
    }];
}

#pragma mark Private

- (FBFuture<NSDictionary<NSString *, id> *> *)fetchInformationFromDiagnosticsRelay
{
  return [[self.device
    startService:DiagnosticsRelayService]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSDictionary<NSString *, id> *result = [connection sendAndReceiveMessage:@{@"Request": @"All"} error:&error];
      if (!result) {
        return [FBFuture futureWithError:error];
      }
      if (![result[@"Status"] isEqualToString:@"Success"]) {
        return [[FBControlCoreError
          describeFormat:@"Not successful %@", result]
          failFuture];
      }
      return [FBFuture futureWithResult:[FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:result[@"Diagnostics"]]];
    }];
}

- (FBFuture<NSArray<id> *> *)fetchInformationFromSpringboard
{
  return [[self.device
    startService:SpringboardService]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSArray<id> *result = [connection sendAndReceiveMessage:@{@"command": @"getIconState"} error:&error];
      if (!result) {
        return [FBFuture futureWithError:error];
      }
      result = [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfArray:result];
      return [FBFuture futureWithResult:result];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)fetchInformationFromMobileConfiguration
{
  return [[self.device
    startService:FBManagedConfigService]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      return [[FBManagedConfigClient managedConfigClientWithConnection:connection logger:self.device.logger] getCloudConfiguration];
    }];
}

@end
