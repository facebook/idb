/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetStateChangeNotifier.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>


@interface FBiOSTargetStateChangeNotifier () <FBiOSTargetSetDelegate>

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSString *filePath;
@property (nonatomic, strong, readwrite) FBDeviceSet *deviceSet;
@property (nonatomic, strong, readwrite) FBSimulatorSet *simulatorSet;
@property (nonatomic, strong, readwrite) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readwrite) NSMutableSet<FBiOSTargetStateUpdate *> *targets;

@end

@implementation FBiOSTargetStateChangeNotifier


#pragma mark Initializers

+ (instancetype)notifierToFilePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithFilePath:filePath logger:logger];
}

- (instancetype)initWithFilePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _logger = logger;
  _filePath = filePath;
  BOOL didCreateFile = [[NSFileManager defaultManager] createFileAtPath:_filePath
                                                               contents:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]
                                                             attributes:@{NSFilePosixPermissions: [NSNumber numberWithShort:0666]}];
  if (!didCreateFile) {
    [logger.error logFormat:@"Failed to create local targets file: %s", strerror(errno)];
    exit(1);
  }
  _targets = [[NSMutableSet alloc] init];
  return self;
}

#pragma mark Public

- (FBFuture<FBFuture<NSNull *> *> *)startNotifier
{
  NSError *error = nil;
  self.deviceSet = [FBDeviceSet defaultSetWithLogger:_logger error:&error delegate:self];
  if (!self.deviceSet) {
    [FBFuture futureWithError:error];
  }
  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:nil
    options:0
    logger:self.logger
    reporter:nil];
  FBSimulatorServiceContext *serviceContext = [FBSimulatorServiceContext sharedServiceContext];
  SimDeviceSet *simDeviceSet = [serviceContext createDeviceSetWithConfiguration:configuration error:&error];
  if (!simDeviceSet) {
    return [FBFuture futureWithError:error];
  }
  self.simulatorSet = [FBSimulatorSet setWithConfiguration:configuration deviceSet:simDeviceSet delegate:self logger:self.logger reporter:nil error:&error];
  if (!self.simulatorSet) {
    return [FBFuture futureWithError:error];
  }
  [self reportInitialState];

  // The notifier never terminates, fallback here is a terrible hack to retain self
  return [[FBFuture futureWithResult:FBMutableFuture.future] fallback:self];
}

#pragma mark Private

- (void)reportInitialState
{
  for (FBDevice *device in self.deviceSet.allDevices) {
    [_targets addObject:[[FBiOSTargetStateUpdate alloc] initWithUDID:device.udid state:device.state type:FBiOSTargetTypeDevice name:device.name osVersion:device.osVersion architecture:device.architecture]];
  }
  for (FBSimulator *simulator in self.simulatorSet.allSimulators) {
    [_targets addObject:[[FBiOSTargetStateUpdate alloc] initWithUDID:simulator.udid state:simulator.state type:FBiOSTargetTypeSimulator name:simulator.name osVersion:simulator.osVersion architecture:simulator.architecture]];
  }
  [self writeTargets];
  NSData *jsonOutput = [NSJSONSerialization dataWithJSONObject:@{@"report_initial_state": @YES} options:0 error:nil];
  NSMutableData *readyOutput = [NSMutableData dataWithData:jsonOutput];
  [readyOutput appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  write(STDOUT_FILENO, readyOutput.bytes, readyOutput.length);
  fflush(stdout);
}

- (void)writeTargets
{
  NSError *error = nil;
  NSMutableArray<id<FBJSONSerializable>> *jsonArray = [[NSMutableArray alloc] init];
  for (FBiOSTargetStateUpdate *target in _targets.allObjects) {
       [jsonArray addObject:target.jsonSerializableRepresentation];
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:jsonArray options:0 error:&error];
  if (!data) {
    [self.logger logFormat:@"error writing update to consumer %@",error];
    exit(1);
  }
  if (![data writeToFile:_filePath options:NSDataWritingAtomic error:&error]) {
    [self.logger logFormat:@"Failed writing updates %@",error];
    exit(1);
  }
}

#pragma mark FBiOSTargetSet Delegate Methods


- (void)targetDidUpdate:(FBiOSTargetStateUpdate *)update
{
  NSMutableArray<FBiOSTargetStateUpdate *> *targetsToUpdate = [[NSMutableArray alloc] init];
  for (FBiOSTargetStateUpdate *target in self.targets) {
    if ([target.udid isEqualToString:update.udid]) {
      [targetsToUpdate addObject:target];
    }
  }
  for (FBiOSTargetStateUpdate *target in targetsToUpdate) {
    [_targets removeObject:target];
  }
  [_targets addObject:update];
  [self writeTargets];
}
@end
