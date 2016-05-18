/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAugmentedTestManagerAPIMediator.h"

#import <FBControlCore/FBControlCore.h>

#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>

#import <DVTFoundation/DVTDevice.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

void DVTDispatchAsync(__strong dispatch_queue_t queue, __unsafe_unretained dispatch_block_t block);

@interface FBAugmentedProcessProxy : NSObject

@property (nonatomic, assign) int state;
@property (nonatomic, assign) int runnablePID;

@property (nonatomic, strong) id runnableDisplayName;
@property (nonatomic, strong) NSUUID *sessionIdentifier;

@property (nonatomic, weak) id currentDebugSession;
@property (nonatomic, weak) id launchSession;
@property (nonatomic, weak) id testConfiguration;

+ (instancetype)proxyWithPID:(pid_t)PID sessionIdentifier:(NSUUID *)sessionIdentifier;

@end

@interface FBAugmentedTestManagerAPIMediator ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBAugmentedTestManagerAPIMediator

+ (instancetype)mediatorWithDevice:(DVTDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDevice:device testRunnerPID:testRunnerPID sessionIdentifier:sessionIdentifier logger:logger];
}

- (instancetype)initWithDevice:(DVTDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;

  // Setters are used as methods are linkable, but ivars are not.
  [self setValue:[FBAugmentedProcessProxy proxyWithPID:testRunnerPID sessionIdentifier:sessionIdentifier] forKey:@"operation"];
  self.validatorsStack = [NSMutableArray new];
  self.targetDevice = device;
  self.targetArchitecture = device.nativeArchitecture;
  self.testTokensToExecutionTrackers = [NSMutableDictionary dictionary];
  self.executionTrackerObservationTokens = [NSMutableSet set];
  self.delegateBlockQueue = [NSMutableArray new];
  self.consoleChunkQueue = [NSMutableArray new];
  self.consoleBuffer = [NSMutableString new];
  [self _prepareStatusLoggingStream];
  self.targetIsiOSSimulator = [self isKindOfClass:NSClassFromString(@"DVTiPhoneSimulator")];

  return self;
}

- (void)connectTestRunnerWithTestManagerDaemon
{
  _IDETestManagerAPIMediator *xcodeMediator = self;
  DVTDevice *targetDevice = self.targetDevice;
  DVTDispatchAsync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    if (!xcodeMediator.isValid) {
      return;
    }
    id transport = [targetDevice makeTransportForTestManagerService:nil];
    if (!xcodeMediator.isValid) {
      return;
    }
    [xcodeMediator _setupTestBundleConnectionWithTransport:transport];
    DVTDispatchAsync(dispatch_get_main_queue(), ^{
      if (!xcodeMediator.isValid) {
        return;
      }
      [xcodeMediator _handleDaemonConnection:xcodeMediator.connection];
    });
  });
}

- (id)_XCT_launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment
{
  [self.logger logFormat:@"Using log file %@", self.statusLogPath];
  NSError *error;
  DTXRemoteInvocationReceipt *recepit = [DTXRemoteInvocationReceipt new];
  if(![self.delegate testManagerMediator:(FBTestManagerAPIMediator *)self launchProcessWithPath:path bundleID:bundleID arguments:arguments environmentVariables:environment error:&error]) {
    [recepit invokeCompletionWithReturnValue:nil error:error];
  }
  else {
    [recepit invokeCompletionWithReturnValue:@(recepit.hash) error:nil];
  }
  return recepit;
}

- (id)_XCT_getProgressForLaunch:(id)arg1
{
  DTXRemoteInvocationReceipt *recepit = [DTXRemoteInvocationReceipt new];
  [recepit invokeCompletionWithReturnValue:@1 error:nil];
  return recepit;
}

- (void)_logAtLevel:(int)arg1 message:(NSString *)arg2, ... NS_FORMAT_FUNCTION(2, 3)
{
  va_list arguments;
  va_start(arguments, arg2);
  [self.logger logFormat:arg2, arguments];
}

@end

@implementation FBAugmentedProcessProxy

+ (instancetype)proxyWithPID:(pid_t)PID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  FBAugmentedProcessProxy *proxy = [FBAugmentedProcessProxy new];
  proxy.runnablePID = PID;
  proxy.sessionIdentifier = sessionIdentifier;
  proxy.launchSession = proxy;
  proxy.testConfiguration = proxy;
  proxy.runnableDisplayName = @"WebDriverAgentRunner";
  return proxy;
}

- (void)cancel
{
}

@end
