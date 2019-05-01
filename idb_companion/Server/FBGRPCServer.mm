/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBGRPCServer.h"

#import <grpcpp/grpcpp.h>
#import <grpcpp/resource_quota.h>
#import <idbGRPC/idb.grpc.pb.h>

#import "FBIDBCommandExecutor.h"
#import "FBIDBServiceHandler.h"
#import "FBIDBPortsConfiguration.h"

@interface FBGRPCServer ()

@property (nonatomic, strong, readonly) FBIDBPortsConfiguration *ports;
@property (nonatomic, strong, readonly) FBIDBCommandExecutor *commandExecutor;
@property (nonatomic, strong, readonly)  id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBEventReporter> eventReporter;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *serverTerminated;

@property (nonatomic, assign, readwrite) in_port_t selectedPort;

@end

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using grpc::ResourceQuota;
using namespace std;

@implementation FBGRPCServer

#pragma mark Initializers

+ (instancetype)serverWithPorts:(FBIDBPortsConfiguration *)ports target:(id<FBiOSTarget>)target commandExecutor:(FBIDBCommandExecutor *)commandExecutor eventReporter:(id<FBEventReporter>)eventReporter logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithPorts:ports target:target commandExecutor:commandExecutor eventReporter:eventReporter logger:logger];
}

- (instancetype)initWithPorts:(FBIDBPortsConfiguration *)ports target:(id<FBiOSTarget>)target commandExecutor:(FBIDBCommandExecutor *)commandExecutor eventReporter:(id<FBEventReporter>)eventReporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _ports = ports;
  _target = target;
  _commandExecutor = commandExecutor;
  _eventReporter = eventReporter;
  _logger = logger;
  _serverTerminated = FBMutableFuture.future;

  return self;
}

#pragma mark FBIDBCompanionServer

- (FBFuture<NSNull *> *)start
{
  putenv((char *)"GRPC_TRACE=all");
  putenv((char *)"GRPC_VERBOSITY=DEBUG");
  dispatch_queue_t queue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  FBMutableFuture<NSNull *> *serverStarted = FBMutableFuture.future;
  dispatch_async(queue, ^(void){
    [self.logger logFormat:@"Starting GRPC server on port %u", self.ports.grpcPort];
    string server_address("0.0.0.0:" + std::to_string(self.ports.grpcPort));
    FBIDBServiceHandler service = FBIDBServiceHandler(self.commandExecutor, self.target, self.eventReporter, self.ports);
    int selectedPort = self.ports.grpcPort;
    unique_ptr<Server> server(ServerBuilder()
      .AddListeningPort(server_address, grpc::InsecureServerCredentials(), &selectedPort)
      .RegisterService(&service)
      .SetResourceQuota(ResourceQuota("idb_resource.quota").SetMaxThreads(10))
      .SetMaxReceiveMessageSize(16777216) // 16MB (16 * 1024 * 1024). Default is 4MB (4 * 1024 * 1024)
      .BuildAndStart()
    );
    self.selectedPort = selectedPort;

    [serverStarted resolveWithResult:NSNull.null];
    [self.logger.info logFormat:@"Started GRPC server on port %u", selectedPort];
    server->Wait();
    [self.logger.info logFormat:@"GRPC server is no longer running on port %u", selectedPort];
    [self.serverTerminated resolveWithResult:NSNull.null];
  });
  return serverStarted;
}

- (FBFuture<NSNull *> *)completed
{
  return self.serverTerminated;
}

- (NSString *)futureType
{
  return @"grpc_server";
}

- (id)jsonSerializableRepresentation
{
  return @{@"grpc_port": @(self.selectedPort)};
}

@end
