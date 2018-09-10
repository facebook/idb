/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceCrashLogCommands.h"

#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"
#import "FBAMDServiceConnection.h"
#import "FBAFCConnection.h"

@interface FBDeviceCrashLogCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, strong, readonly) FBCrashLogStore *store;
@property (nonatomic, assign, readwrite) BOOL hasPerformedInitialIngestion;

@end

@implementation FBDeviceCrashLogCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  NSString *storeDirectory = [target.auxillaryDirectory stringByAppendingPathComponent:@"crash_store"];
  FBCrashLogStore *store = [FBCrashLogStore storeForDirectories:@[storeDirectory] logger:target.logger];
  return [[self alloc] initWithDevice:target store:store];
}

- (instancetype)initWithDevice:(FBDevice *)device store:(FBCrashLogStore *)store
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _store = store;
  _hasPerformedInitialIngestion = NO;

  return self;
}

#pragma mark FBCrashLogCommands

static NSString *const CrashReportMoverService = @"com.apple.crashreportmover";
static NSString *const CrashReportCopyService = @"com.apple.crashreportcopymobile";
static NSString *const PingSuccess = @"ping";

- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(NSPredicate *)predicate
{
  [self ingestAllCrashLogs];
  return [self.store nextCrashLogForMatchingPredicate:predicate];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crashes:(NSPredicate *)predicate
{
  return [[self
    ingestAllCrashLogs]
    onQueue:self.device.workQueue map:^(NSArray<FBCrashLogInfo *> *_) {
      return [self.store ingestedCrashLogsMatchingPredicate:predicate];
    }];
}

#pragma mark Private

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)ingestAllCrashLogs
{
  return [[[self.device.amDevice
    startService:CrashReportMoverService]
    onQueue:self.device.asyncQueue fmap:^ FBFuture<FBAMDServiceConnection *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSData *data = [connection receive:4 error:&error];
      if (!data) {
        return [[[FBDeviceControlError
          describeFormat:@"Failed to get pingback from %@", CrashReportMoverService]
          causedBy:error]
          failFuture];
      }
      NSString *response = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
      if (![response isEqualToString:PingSuccess]) {
        return [[[FBDeviceControlError
          describeFormat:@"Pingback from %@ is '%@' not '%@'", CrashReportMoverService, response, PingSuccess]
          causedBy:error]
          failFuture];
      }
      if (!self.hasPerformedInitialIngestion) {
        [self.store ingestAllExistingInDirectory];
        self.hasPerformedInitialIngestion = YES;
      }
      return [FBFuture futureWithResult:response];
    }]
    onQueue:self.device.workQueue fmap:^(id _) {
      return [[self.device.amDevice
        startService:CrashReportCopyService]
        onQueue:self.device.asyncQueue fmap:^ FBFuture<NSArray<FBCrashLogInfo *> *> * (FBAMDServiceConnection *connection) {
          NSError *error = nil;
          FBAFCConnection *afc = [FBAFCConnection afcFromServiceConnection:connection calls:FBAFCConnection.defaultCalls logger:connection.logger error:&error];
          if (!afc) {
            return [FBFuture futureWithError:error];
          }
          NSArray<NSString *> *paths = [afc contentsOfDirectory:@"." error:&error];
          if (!paths) {
            return [FBFuture futureWithError:error];
          }
          NSMutableArray<FBCrashLogInfo *> *crashes = [NSMutableArray array];
          for (NSString *path in paths) {
            FBCrashLogInfo *crash = [self crashLogInfo:afc path:path error:nil];
            if (!crash) {
              continue;
            }
            [crashes addObject:crash];
          }
          return [FBFuture futureWithResult:crashes];
      }];
    }];
}

- (nullable FBCrashLogInfo *)crashLogInfo:(FBAFCConnection *)afc path:(NSString *)path error:(NSError **)error
{
  NSString *name = path;
  if ([self.store hasIngestedCrashLogWithName:name]) {
    return nil;
  }
  NSData *data = [afc contentsOfPath:path error:error];
  if (!data) {
    return nil;
  }
  return [self.store ingestCrashLogData:data name:name];
}

@end
