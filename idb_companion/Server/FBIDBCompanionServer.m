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
#import "FBIDBLogger.h"

@interface FBIDBCompanionServer ()

@property (nonatomic, strong, readonly) FBGRPCServer *server;

@end

@implementation FBIDBCompanionServer

#pragma mark Initializers

+ (instancetype)companionForTarget:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory ports:(FBIDBPortsConfiguration *)ports eventReporter:(id<FBEventReporter>)eventReporter logger:(FBIDBLogger *)logger error:(NSError **)error
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
    logger:logger];
  commandExecutor = [FBLoggingWrapper wrap:commandExecutor eventReporter:eventReporter logger:nil];

  return [self serverWithPorts:ports target:target commandExecutor:commandExecutor eventReporter:eventReporter logger:logger];
}

+ (instancetype)serverWithPorts:(FBIDBPortsConfiguration *)ports target:(id<FBiOSTarget>)target commandExecutor:(FBIDBCommandExecutor *)commandExecutor eventReporter:(id<FBEventReporter>)eventReporter logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithServer:[FBGRPCServer serverWithPorts:ports target:target commandExecutor:commandExecutor eventReporter:eventReporter logger:logger]];
}

- (instancetype)initWithServer:(FBGRPCServer *)server
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _server = server;

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
    futureWithResult:[_server start]]
    mapReplace:_server];
}

- (FBFuture<NSNull *> *)completed
{
  return [[FBFuture futureWithResult:[self.server completed]] mapReplace:_server];
}

- (NSString *)futureType
{
  return @"companion";
}

#pragma mark FBJSONSerialization

- (id)jsonSerializableRepresentation
{
  return _server.jsonSerializableRepresentation;
}

@end
