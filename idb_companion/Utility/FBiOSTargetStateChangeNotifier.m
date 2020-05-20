/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetStateChangeNotifier.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>

#import "FBIDBError.h"

@interface FBiOSTargetStateChangeNotifier () <FBiOSTargetSetDelegate>

@property (nonatomic, strong, readonly, nullable) NSString *filePath;
@property (nonatomic, strong, readonly) FBDeviceSet *deviceSet;
@property (nonatomic, strong, readonly) FBSimulatorSet *simulatorSet;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableSet<FBiOSTargetStateUpdate *> *targets;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *finished;

@end

@implementation FBiOSTargetStateChangeNotifier

#pragma mark Initializers

+ (FBFuture<FBiOSTargetStateChangeNotifier *> *)notifierToFilePath:(NSString *)filePath simulatorSet:(FBSimulatorSet *)simulatorSet deviceSet:(FBDeviceSet *)deviceSet logger:(id<FBControlCoreLogger>)logger
{
  BOOL didCreateFile = [NSFileManager.defaultManager
    createFileAtPath:filePath
    contents:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]
    attributes:@{NSFilePosixPermissions: [NSNumber numberWithShort:0666]}];

  if (!didCreateFile) {
    return [[FBIDBError
      describeFormat:@"Failed to create local targets file: %@ %s", filePath, strerror(errno)]
      failFuture];
  }
  FBiOSTargetStateChangeNotifier *notifier = [[self alloc] initWithFilePath:filePath simulatorSet:simulatorSet deviceSet:deviceSet logger:logger];
  simulatorSet.delegate = notifier;
  deviceSet.delegate = notifier;
  return [FBFuture futureWithResult:notifier];
}

+ (FBFuture<FBiOSTargetStateChangeNotifier *> *)notifierToStdOutWithSimulatorSet:(FBSimulatorSet *)simulatorSet deviceSet:(FBDeviceSet *)deviceSet logger:(id<FBControlCoreLogger>)logger
{
  FBiOSTargetStateChangeNotifier *notifier = [[self alloc] initWithFilePath:nil simulatorSet:simulatorSet deviceSet:deviceSet logger:logger];
  simulatorSet.delegate = notifier;
  deviceSet.delegate = notifier;
  return [FBFuture futureWithResult:notifier];
}

- (instancetype)initWithFilePath:(nullable NSString *)filePath simulatorSet:(FBSimulatorSet *)simulatorSet deviceSet:(FBDeviceSet *)deviceSet logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  _simulatorSet = simulatorSet;
  _deviceSet = deviceSet;
  _logger = logger;
  _targets = [[NSMutableSet alloc] init];
  _finished = FBMutableFuture.future;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startNotifier
{
  for (FBDevice *device in self.deviceSet.allDevices) {
    [_targets addObject:[[FBiOSTargetStateUpdate alloc] initWithUDID:device.udid state:device.state type:FBiOSTargetTypeDevice name:device.name osVersion:device.osVersion architecture:device.architecture]];
  }
  for (FBSimulator *simulator in self.simulatorSet.allSimulators) {
    [_targets addObject:[[FBiOSTargetStateUpdate alloc] initWithUDID:simulator.udid state:simulator.state type:FBiOSTargetTypeSimulator name:simulator.name osVersion:simulator.osVersion architecture:simulator.architecture]];
  }
  if (![self writeTargets]) {
    return self.finished;
  }
  // If we're writing to a file, we also need to signal to stdout on the first update
  if (self.filePath) {
    NSData *jsonOutput = [NSJSONSerialization dataWithJSONObject:@{@"report_initial_state": @YES} options:0 error:nil];
    NSMutableData *readyOutput = [NSMutableData dataWithData:jsonOutput];
    [readyOutput appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    write(STDOUT_FILENO, readyOutput.bytes, readyOutput.length);
    fflush(stdout);
  }

  return FBFuture.empty;
}

- (FBFuture<NSNull *> *)notifierDone
{
  return self.finished;
}

#pragma mark Private

- (BOOL)writeTargets
{
  NSError *error = nil;
  NSMutableArray<id<FBJSONSerializable>> *jsonArray = [[NSMutableArray alloc] init];
  for (FBiOSTargetStateUpdate *target in _targets.allObjects) {
    [jsonArray addObject:target.jsonSerializableRepresentation];
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:jsonArray options:0 error:&error];
  if (!data) {
    [self.finished resolveWithError:[[FBIDBError describeFormat:@"error writing update to consumer %@", error] build]];
    return NO;
  }
  NSString *filePath = self.filePath;
  return filePath ? [self writeTargetsData:data toFilePath:filePath] : [self writeTargetsDataToStdOut:data];
}

- (BOOL)writeTargetsData:(NSData *)data toFilePath:(NSString *)filePath
{
  NSError *error = nil;
  if (![data writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
    [self.logger logFormat:@"Failed writing updates %@", error];
    [self.finished resolveWithError:[[FBIDBError describeFormat:@"Failed writing updates %@", error] build]];
    return NO;
  }
  return YES;
}

- (BOOL)writeTargetsDataToStdOut:(NSData *)data
{
  write(STDOUT_FILENO, data.bytes, data.length);
  data = FBDataBuffer.newlineTerminal;
  write(STDOUT_FILENO, data.bytes, data.length);
  fflush(stdout);
  return YES;
}

#pragma mark FBiOSTargetSetDelegate Methods

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
