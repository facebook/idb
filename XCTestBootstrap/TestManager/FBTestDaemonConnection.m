/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestDaemonConnection.h"

#import <XCTest/XCTestDriverInterface-Protocol.h>
#import <XCTest/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <FBControlCore/FBControlCore.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXTransport.h>
#import <DTXConnectionServices/DTXSocketTransport.h>

#import <objc/runtime.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerContext.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestDaemonConnection ()

@property (nonatomic, strong, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBTestDaemonConnection

#pragma mark Initializers

+ (FBFutureContext<NSNull *> *)daemonConnectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  FBTestDaemonConnection *connection = [[self alloc] initWithWithContext:context target:target interface:interface requestQueue:requestQueue logger:logger];
  return [connection connect];
}

- (instancetype)initWithWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _interface = interface;
  _requestQueue = requestQueue;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFutureContext<NSNull *> *)connect
{
  [self.logger log:@"Starting the daemon connection"];
  return [[FBTestManagerAPIMediator
    testmanagerdConnectionWithTarget:self.target queue:self.requestQueue logger:self.logger]
    onQueue:self.requestQueue pend:^(DTXConnection *connection) {
      id<XCTestManager_DaemonConnectionInterface> daemonProxy = [self createDaemonProxyWithConnection:connection];
      return [[FBTestDaemonConnection
        initateControlSession:daemonProxy testProcess:self.context.testRunnerPID logger:self.logger]
        mapReplace:NSNull.null];
    }];
}

#pragma mark Private

- (id<XCTestManager_DaemonConnectionInterface>)createDaemonProxyWithConnection:(DTXConnection *)connection
{
  // The connection must be started/resumed first.
  [self.logger log:@"Resuming the daemon testmanagerd connection"];
  [connection resume];

  DTXProxyChannel *channel = [connection
    makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
    exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [channel setExportedObject:self.interface queue:self.target.workQueue];

  id<XCTestManager_DaemonConnectionInterface> interface = (id<XCTestManager_DaemonConnectionInterface>)channel.remoteObjectProxy;
  [self.logger logFormat:@"Constructed channel for remote interface XCTestManager_DaemonConnectionInterface %@", interface];
  return interface;
}

+ (FBFuture<NSNumber *> *)initateControlSession:(id<XCTestManager_DaemonConnectionInterface>)daemonProxy testProcess:(pid_t)testRunnerPID logger:(id<FBControlCoreLogger>)logger
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;

  [logger logFormat:@"Initiating Control Session for %d", testRunnerPID];
  DTXRemoteInvocationReceipt *receipt = [daemonProxy _IDE_initiateControlSessionForTestProcessID:@(testRunnerPID) protocolVersion:@(FBProtocolVersion)];

  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    [logger logFormat:@"%@ resolved for %@", receipt, NSStringFromSelector(@selector(_IDE_initiateControlSessionForTestProcessID:protocolVersion:))];
    if (error) {
      [logger log:@"Error in establishing daemon connection, trying legacy protocol"];
      [future resolveFromFuture:[self initateControlSessionLegacy:daemonProxy testProcess:testRunnerPID logger:logger]];
      return;
    }
    [logger logFormat:@"Got whitelisting response and daemon protocol version %@", version];
    [future resolveWithResult:version];
  }];

  return future;
}

+ (FBFuture<NSNumber *> *)initateControlSessionLegacy:(id<XCTestManager_DaemonConnectionInterface>)daemonProxy testProcess:(pid_t)testRunnerPID logger:(id<FBControlCoreLogger>)logger
{
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  DTXRemoteInvocationReceipt *receipt = [daemonProxy _IDE_initiateControlSessionForTestProcessID:@(testRunnerPID)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      [logger logFormat:@"Error in whitelisting response from testmanagerd: %@ (%@), ignoring for now.", error.localizedDescription, error.localizedRecoverySuggestion];
      [future resolveWithError:error];
      return;
    }
    [logger logFormat:@"Got legacy whitelisting response, daemon protocol version is %@", version];
    [future resolveWithResult:version];
  }];
  return future;
}

@end
