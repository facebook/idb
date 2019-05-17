/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBCompanionServer.h"

#import "FBIDBStorageManager.h"
#import "FBGRPCServer.h"
#import "FBIDBCommandExecutor.h"
#import "FBIDBError.h"
#import "FBIDBPortsConfiguration.h"
#import "FBIDBCommandExecutor.h"

@interface FBIDBCompanionServer ()

@property (nonatomic, strong, readonly) NSArray<id<FBIDBCompanionServer>> *servers;

@end

@implementation FBIDBCompanionServer

#pragma mark Initializers

+ (instancetype)companionForTarget:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory ports:(FBIDBPortsConfiguration *)ports eventReporter:(id<FBEventReporter>)eventReporter logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  FBIDBStorageManager *storageManager = [FBIDBStorageManager managerForTarget:target logger:logger error:error];
  if (!storageManager) {
    return nil;
  }
  // Command Executor
  FBIDBCommandExecutor *commandExecutor = [FBIDBCommandExecutor
    commandExecutorForTarget:target
    storageManager:storageManager
    temporaryDirectory:temporaryDirectory
    ports:ports
    logger:target.logger];
  commandExecutor = [FBLoggingWrapper wrap:commandExecutor eventReporter:eventReporter logger:nil];

  return [self serverWithPorts:ports target:target commandExecutor:commandExecutor eventReporter:eventReporter logger:target.logger];
}

+ (instancetype)serverWithPorts:(FBIDBPortsConfiguration *)ports target:(id<FBiOSTarget>)target commandExecutor:(FBIDBCommandExecutor *)commandExecutor eventReporter:(id<FBEventReporter>)eventReporter logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray<id<FBIDBCompanionServer>> *servers = NSMutableArray.array;
  for (Class serverClass in self.serverClasses) {
    [servers addObject:[serverClass serverWithPorts:ports target:target commandExecutor:commandExecutor eventReporter:eventReporter logger:logger]];
  }

  return [[self alloc] initWithServers:servers];
}

- (instancetype)initWithServers:(NSArray<id<FBIDBCompanionServer>> *)servers
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _servers = servers;

  return self;
}

#pragma mark Properties

static NSMutableArray<Class> *staticServerClasses;

+ (NSMutableArray<Class> *)serverClasses
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    staticServerClasses = [@[FBGRPCServer.class] mutableCopy];
  });
  return staticServerClasses;
}

#pragma mark FBIDBCompanionServer

- (FBFuture<id<FBIDBCompanionServer>> *)start
{
  return [[FBFuture
    futureWithFutures:[self.servers valueForKey:@"start"]]
    mapReplace:self];
}

- (FBFuture<NSNull *> *)completed
{
  return [[FBFuture
    futureWithFutures:[self.servers valueForKey:@"completed"]]
    mapReplace:NSNull.null];
}

- (NSString *)futureType
{
  return @"companion";
}

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *json = NSMutableDictionary.dictionary;
  for (id<FBIDBCompanionServer> server in self.servers) {
    [json addEntriesFromDictionary:server.jsonSerializableRepresentation];
  }
  return json;
}

@end
