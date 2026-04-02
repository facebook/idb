/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetStateChangeNotifier.h"

#import <CompanionLib/CompanionLib-Swift.h>

#import "FBiOSTargetDescription.h"

@interface FBiOSTargetStateChangeNotifier () <FBiOSTargetSetDelegate>

@property (nullable, nonatomic, readonly, strong) NSString *filePath;
@property (nonnull, nonatomic, readonly, strong) NSArray<id<FBiOSTargetSet>> *targetSets;
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nonnull, nonatomic, readonly, strong) NSMutableDictionary<NSString *, FBiOSTargetDescription *> *current;
@property (nonnull, nonatomic, readonly, strong) FBMutableFuture<NSNull *> *finished;

@end

@implementation FBiOSTargetStateChangeNotifier

#pragma mark Initializers

+ (FBFuture<FBiOSTargetStateChangeNotifier *> *)notifierToFilePath:(NSString *)filePath withTargetSets:(NSArray<id<FBiOSTargetSet>> *)targetSets logger:(id<FBControlCoreLogger>)logger
{
  if (targetSets.count == 0) {
    return [[FBIDBError
             describe:@"Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor"]
            failFuture];
  }

  BOOL didCreateFile = [NSFileManager.defaultManager
                        createFileAtPath:filePath
                        contents:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]
                        attributes:@{NSFilePosixPermissions : [NSNumber numberWithShort:0666]}];

  if (!didCreateFile) {
    return [[FBIDBError
             describe:[NSString stringWithFormat:@"Failed to create local targets file: %@ %s", filePath, strerror(errno)]]
            failFuture];
  }
  FBiOSTargetStateChangeNotifier *notifier = [[self alloc] initWithFilePath:filePath targetSets:targetSets logger:logger];
  for (id<FBiOSTargetSet> targetSet in targetSets) {
    targetSet.delegate = notifier;
  }
  return [FBFuture futureWithResult:notifier];
}

+ (FBFuture<FBiOSTargetStateChangeNotifier *> *)notifierToStdOutWithTargetSets:(NSArray<id<FBiOSTargetSet>> *)targetSets logger:(id<FBControlCoreLogger>)logger
{
  if (targetSets.count == 0) {
    return [[FBIDBError
             describe:@"Cannot initialize FBiOSTargetStateChangeNotifier without any sets to monitor"]
            failFuture];
  }

  FBiOSTargetStateChangeNotifier *notifier = [[self alloc] initWithFilePath:nil targetSets:targetSets logger:logger];
  for (id<FBiOSTargetSet> targetSet in targetSets) {
    targetSet.delegate = notifier;
  }
  return [FBFuture futureWithResult:notifier];
}

- (nullable instancetype)initWithFilePath:(nullable NSString *)filePath targetSets:(nonnull NSArray<id<FBiOSTargetSet>> *)targetSets logger:(nonnull id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  _targetSets = targetSets;
  _logger = logger;
  _current = NSMutableDictionary.dictionary;
  _finished = FBMutableFuture.future;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startNotifier
{
  for (id<FBiOSTargetSet> targetSet in self.targetSets) {
    for (id<FBiOSTargetInfo> target in targetSet.allTargetInfos) {
      self.current[target.uniqueIdentifier] = [[FBiOSTargetDescription alloc] initWithTarget:target];
    }
  }
  if (![self writeTargets]) {
    return self.finished;
  }
  // If we're writing to a file, we also need to signal to stdout on the first update
  if (self.filePath) {
    NSData *jsonOutput = [NSJSONSerialization dataWithJSONObject:@{@"report_initial_state" : @YES} options:0 error:nil];
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
  NSMutableArray<NSDictionary<NSString *, id> *> *jsonArray = [[NSMutableArray alloc] init];
  for (FBiOSTargetDescription *target in self.current.allValues) {
    [jsonArray addObject:target.asJSON];
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:jsonArray options:0 error:&error];
  if (!data) {
    [self.finished resolveWithError:[[FBIDBError describe:[NSString stringWithFormat:@"error writing update to consumer %@", error]] build]];
    return NO;
  }
  NSString *filePath = self.filePath;
  return filePath ? [self writeTargetsData:data toFilePath:filePath] : [self writeTargetsDataToStdOut:data];
}

- (BOOL)writeTargetsData:(nonnull NSData *)data toFilePath:(nonnull NSString *)filePath
{
  NSError *error = nil;
  if (![data writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
    [self.logger log:[NSString stringWithFormat:@"Failed writing updates %@", error]];
    [self.finished resolveWithError:[[FBIDBError describe:[NSString stringWithFormat:@"Failed writing updates %@", error]] build]];
    return NO;
  }
  return YES;
}

- (BOOL)writeTargetsDataToStdOut:(nonnull NSData *)data
{
  write(STDOUT_FILENO, data.bytes, data.length);
  data = FBDataBuffer.newlineTerminal;
  write(STDOUT_FILENO, data.bytes, data.length);
  fflush(stdout);
  return YES;
}

#pragma mark FBiOSTargetSetDelegate Methods

- (void)targetAdded:(nonnull id<FBiOSTargetInfo>)targetInfo inTargetSet:(nonnull id<FBiOSTargetSet>)targetSet
{
  self.current[targetInfo.uniqueIdentifier] = [[FBiOSTargetDescription alloc] initWithTarget:targetInfo];
  [self writeTargets];
}

- (void)targetRemoved:(nonnull id<FBiOSTargetInfo>)targetInfo inTargetSet:(nonnull id<FBiOSTargetSet>)targetSet
{
  [self.current removeObjectForKey:targetInfo.uniqueIdentifier];
  [self writeTargets];
}

- (void)targetUpdated:(nonnull id<FBiOSTargetInfo>)targetInfo inTargetSet:(nonnull id<FBiOSTargetSet>)targetSet
{
  self.current[targetInfo.uniqueIdentifier] = [[FBiOSTargetDescription alloc] initWithTarget:targetInfo];
  [self writeTargets];
}

@end
