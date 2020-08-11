/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceCrashLogCommands.h"

#import "FBAFCConnection.h"
#import "FBAMDServiceConnection.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceApplicationCommands.h"
#import "FBDeviceControlError.h"
#import "FBDeviceFileCommands.h"

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
  [self ingestAllCrashLogs:NO];
  return [self.store nextCrashLogForMatchingPredicate:predicate];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crashes:(NSPredicate *)predicate useCache:(BOOL)useCache
{
  return [[self
    ingestAllCrashLogs:useCache]
    onQueue:self.device.workQueue map:^(NSArray<FBCrashLogInfo *> *_) {
      return [self.store ingestedCrashLogsMatchingPredicate:predicate];
    }];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)pruneCrashes:(NSPredicate *)predicate
{
  id<FBControlCoreLogger> logger = [self.device.logger withName:@"crash_remove"];
  return [[self
    ingestAllCrashLogs:YES]
    onQueue:self.device.workQueue fmap:^(NSArray<FBCrashLogInfo *> *_) {
      NSArray<FBCrashLogInfo *> *pruned = [self.store pruneCrashLogsMatchingPredicate:predicate];
      [logger logFormat:@"Pruned %@ logs from local cache", [FBCollectionInformation oneLineDescriptionFromArray:[pruned valueForKeyPath:@"name"]]];
      return [self removeCrashLogsFromDevice:pruned logger:logger];
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)crashLogFiles
{
  return [[self
    crashReportFileConnection]
    onQueue:self.device.asyncQueue pend:^(FBAFCConnection *connection) {
      return [FBFuture futureWithResult:[[FBDeviceFileContainer alloc] initWithAFCConnection:connection queue:self.device.asyncQueue]];
    }];
}

#pragma mark Private

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)ingestAllCrashLogs:(BOOL)useCache
{
  if (self.hasPerformedInitialIngestion && useCache) {
    return [FBFuture futureWithResult:@[]];
  }

  id<FBControlCoreLogger> logger = self.device.logger;
  return [[self
    moveCrashReports]
    onQueue:self.device.workQueue fmap:^(NSString *_) {
      return [[self
        crashReportFileConnection]
        onQueue:self.device.workQueue pop:^(FBAFCConnection *afc) {
          if (!self.hasPerformedInitialIngestion) {
            [self.store ingestAllExistingInDirectory];
            self.hasPerformedInitialIngestion = YES;
          }
          NSError *error = nil;
          NSArray<NSString *> *paths = [afc contentsOfDirectory:@"." error:&error];
          if (!paths) {
            return [FBFuture futureWithError:error];
          }
          NSMutableArray<FBCrashLogInfo *> *crashes = [NSMutableArray array];
          for (NSString *path in paths) {
            FBCrashLogInfo *crash = [self crashLogInfo:afc path:path error:&error];
            if (!crash) {
              [logger logFormat:@"Failed to ingest crash log %@: %@", path, error];
              continue;
            }
            [crashes addObject:crash];
          }
          return [FBFuture futureWithResult:crashes];
        }];
    }];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)removeCrashLogsFromDevice:(NSArray<FBCrashLogInfo *> *)crashesToRemove logger:(id<FBControlCoreLogger>)logger
{
  return [[self
    crashReportFileConnection]
    onQueue:self.device.workQueue pop:^(FBAFCConnection *afc) {
      NSMutableArray<FBCrashLogInfo *> *removed = NSMutableArray.array;
      for (FBCrashLogInfo *crash in crashesToRemove) {
        NSError *error = nil;
        if ([afc removePath:crash.name recursively:NO error:&error]) {
          [logger logFormat:@"Crash %@ removed from device", crash.name];
          [removed addObject:crash];
        } else {
          [logger logFormat:@"Crash %@ could not be removed from device: %@", crash.name, error];
        }
      }
      return [FBFuture futureWithResult:removed];
    }];
}

- (nullable FBCrashLogInfo *)crashLogInfo:(FBAFCConnection *)afc path:(NSString *)path error:(NSError **)error
{
  NSString *name = path;
  FBCrashLogInfo *existing = [self.store ingestedCrashLogWithName:path];
  if (existing) {
    [self.device.logger logFormat:@"No need to re-ingest %@", path];
    return existing;
  }
  NSData *data = [afc contentsOfPath:path error:error];
  if (!data) {
    return nil;
  }
  return [self.store ingestCrashLogData:data name:name];
}

- (FBFuture<NSString *> *)moveCrashReports
{
  return [[self.device
    startService:CrashReportMoverService]
    // The mover is used first and can be discarded when done.
    onQueue:self.device.asyncQueue pop:^ FBFuture<NSString *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSData *data = [connection.serviceConnectionWrapped receive:4 error:&error];
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
      return [FBFuture futureWithResult:response];
    }];
}

- (FBFutureContext<FBAFCConnection *> *)crashReportFileConnection
{
  return [[self.device
    startService:CrashReportCopyService]
    // Re-map this into a AFC Connection.
    onQueue:self.device.workQueue push:^(FBAMDServiceConnection *connection) {
      return [FBAFCConnection afcFromServiceConnection:connection calls:FBAFCConnection.defaultCalls logger:self.device.logger queue:self.device.workQueue];
    }];
}

@end
