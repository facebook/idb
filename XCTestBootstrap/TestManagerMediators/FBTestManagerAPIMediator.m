// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBTestManagerAPIMediator.h"

#import <XCTest/XCTestDriverInterface-Protocol.h>
#import <XCTest/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXTransport.h>

#import <IDEiOSSupportCore/DVTAbstractiOSDevice.h>

#define weakify(target) __weak __typeof__(target) weak_##target = target
#define strongify(target) \
          _Pragma("clang diagnostic push") \
          _Pragma("clang diagnostic ignored \"-Wshadow\"") \
          __strong __typeof__(weak_##target) self = weak_##target; \
          _Pragma("clang diagnostic pop")


static const NSInteger FBProtocolVersion = 0x10;
static const NSInteger FBProtocolMinimumVersion = 0x8;

static const NSInteger FBErrorCodeStartupFailure = 0x3;
static const NSInteger FBErrorCodeLostConnection = 0x4;


@interface FBTestManagerAPIMediator () <XCTestManager_IDEInterface>
@property (nonatomic, strong) DVTDevice *targetDevice;
@property (nonatomic, assign) BOOL targetIsiOSSimulator;

@property (nonatomic, assign) pid_t testRunnerPID;
@property (nonatomic, strong) NSUUID *sessionIdentifier;

@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL hasFailed;
@property (nonatomic, assign) BOOL testingIsFinished;
@property (nonatomic, assign) BOOL testPlanDidStartExecuting;

@property (nonatomic, assign) long long testBundleProtocolVersion;
@property (nonatomic, strong) id<XCTestDriverInterface> testBundleProxy;
@property (nonatomic, strong) DTXConnection *testBundleConnection;

@property (nonatomic, assign) long long daemonProtocolVersion;
@property (nonatomic, strong) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (nonatomic, strong) DTXConnection *daemonConnection;

@property (nonatomic, assign) NSTimeInterval defaultTimeout;
@property (nonatomic, strong) NSTimer *startupTimeoutTimer;
@end

@implementation FBTestManagerAPIMediator

+ (NSString *)clientProcessUniqueIdentifier
{
  static dispatch_once_t onceToken;
  static NSString *_clientProcessUniqueIdentifier;
  dispatch_once(&onceToken, ^{
    _clientProcessUniqueIdentifier = [NSProcessInfo processInfo].globallyUniqueString;
  });
  return _clientProcessUniqueIdentifier;
}


#pragma mark - Public

+ (instancetype)mediatorWithDevice:(DVTAbstractiOSDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  FBTestManagerAPIMediator *mediator = [self.class new];
  mediator.defaultTimeout = 120;
  mediator.targetDevice = device;
  mediator.targetIsiOSSimulator = [self isKindOfClass:NSClassFromString(@"DVTiPhoneSimulator")];
  mediator.sessionIdentifier = sessionIdentifier;
  mediator.testRunnerPID = testRunnerPID;
  return mediator;
}

- (void)connectTestRunnerWithTestManagerDaemon
{
  [self makeTransportWithSuccessBlock:^(DTXTransport *transport) {
    [self setupTestBundleConnectionWithTransport:transport];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self sendStartSessionRequestToTestManager];
    });
  }];
}


#pragma mark - Private

- (void)setupTestBundleConnectionWithTransport:(DTXTransport *)transport
{
  [self logTestManagerMessage:@"Creating the connection."];
  DTXConnection *connection = [[DTXConnection alloc] initWithTransport:transport];

  weakify(self);
  [connection registerDisconnectHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      strongify(self);
      if (self.testPlanDidStartExecuting) {
        [self reportStartupFailure:@"Lost connection to test process" errorCode:FBErrorCodeLostConnection];
      }
    });
  }];
  [self logTestManagerMessage:@"Listening for proxy connection request from the test bundle (all platforms)"];
  [connection handleProxyRequestForInterface:@protocol(XCTestManager_IDEInterface)
                               peerInterface:@protocol(XCTestDriverInterface)
                                     handler:^(DTXProxyChannel *channel){
    strongify(self);
    [self logTestManagerMessage:@"Got proxy channel request from test bundle"];
    [channel setExportedObject:self queue:dispatch_get_main_queue()];
    self.testBundleProxy = channel.remoteObjectProxy;
  }];
  self.testBundleConnection = connection;
  [self logTestManagerMessage:@"Resuming the connection."];
  [self.testBundleConnection resume];
}

- (void)sendStartSessionRequestToTestManager
{
  if (self.hasFailed) {
    [self logTestManagerMessage:@"Mediator has already failed skipping."];
    return;
  }

  [self reportStartupProgress:@"Checking test manager availability..." withTimeoutInterval:self.defaultTimeout];
  DTXProxyChannel *proxyChannel =
  [self.testBundleConnection makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
                                               exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [proxyChannel setExportedObject:self queue:dispatch_get_main_queue()];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>)[proxyChannel remoteObjectProxy];

  NSString *bundlePath = [NSBundle mainBundle].bundlePath;
  if (![[NSBundle mainBundle].bundlePath.pathExtension isEqualToString:@"app"]) {
    bundlePath = [NSBundle mainBundle].executablePath;
  }

  [self logTestManagerMessage:@"Starting test session with ID %@", self.sessionIdentifier];

  DTXRemoteInvocationReceipt *receipt =
  [remoteProxy _IDE_initiateSessionWithIdentifier:self.sessionIdentifier
                                        forClient:self.class.clientProcessUniqueIdentifier
                                           atPath:bundlePath
                                  protocolVersion:@(FBProtocolVersion)];
  weakify(self);
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    strongify(self);
    if (!self) {
      [self logTestManagerMessage:@"Strong self should not be nil"];
      return;
    }
    if (!self) { // Possibly '!error'
      // First if in __54-[_IDETestManagerAPIMediator _handleDaemonConnection:]_block_invoke_2
      [self __beginSessionWithBundlePath:bundlePath remoteProxy:remoteProxy proxyChannel:proxyChannel];
      return;
    }
    [self finilzeConnectionWithProxyChannel:proxyChannel error:error];
  }];
}

- (void)finilzeConnectionWithProxyChannel:(DTXProxyChannel *)proxyChannel error:(NSError *)error
{
  [proxyChannel cancel];
  if (error) {
    [self logTestManagerMessage:@"Error from testmanagerd: %@ (%@)", error.localizedDescription, error.localizedRecoverySuggestion];
    [self reportStartupFailure:error.localizedDescription errorCode:FBErrorCodeStartupFailure];
    return;
  }
  [self logTestManagerMessage:@"Testmanagerd handled session request."];
  [self.startupTimeoutTimer invalidate];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.hasFailed) {
      [self logTestManagerMessage:@"Mediator has already failed skipping."];
      return;
    }
    [self logTestManagerMessage:@"Waiting for test process to launch."];
  });
}

- (void)whitelistTestProcessIDForUITesting
{
  [self logTestManagerMessage:@"Creating secondary transport and connection for whitelisting test process PID."];
  [self makeTransportWithSuccessBlock:^(DTXTransport *transport) {
    [self setupDaemonConnectionWithTransport:transport];
  }];
}

- (void)setupDaemonConnectionWithTransport:(DTXTransport *)transport
{
  DTXConnection *connection = [[DTXConnection alloc] initWithTransport:transport];
  weakify(self);
  [connection registerDisconnectHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      strongify(self);
      [self reportStartupFailure:@"Lost connection to test manager service." errorCode:FBErrorCodeLostConnection];
    });
  }];
  [self logTestManagerMessage:@"Resuming the secondary connection."];
  self.daemonConnection = connection;
  [connection resume];
  DTXProxyChannel *channel =
  [connection makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
                                exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [channel setExportedObject:self queue:dispatch_get_main_queue()];
  self.daemonProxy = (id<XCTestManager_DaemonConnectionInterface>)channel.remoteObjectProxy;

  [self logTestManagerMessage:@"Whitelisting test process ID %d", self.testRunnerPID];
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID) protocolVersion:@(FBProtocolVersion)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    strongify(self);
    if (error) {
      [self setupDaemonConnectionViaLegacyProtocol];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self logTestManagerMessage:@"Got whitelisting response and daemon protocol version %lld", self.daemonProtocolVersion];
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:version];
  }];
}

- (void)setupDaemonConnectionViaLegacyProtocol
{
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID)];
  weakify(self);
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    strongify(self);
    if (error) {
      [self logTestManagerMessage:@"Error in whitelisting response from testmanagerd: %@ (%@), ignoring for now.", error.localizedDescription, error.localizedRecoverySuggestion];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self logTestManagerMessage:@"Got legacy whitelisting response, daemon protocol version is 14"];
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
  }];
}

- (void)makeTransportWithSuccessBlock:(void(^)(DTXTransport *))successBlock
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *error;
    DTXTransport *transport = [self.targetDevice makeTransportForTestManagerService:&error];
    if (error) {
      [self logTestManagerMessage:@"Failure to create transport for test daemon:\n%@", error.userInfo[@"DetailedDescriptionKey"] ?: @""];
    }
    if (!transport) {
      [self reportStartupFailure:error.localizedFailureReason errorCode:FBErrorCodeStartupFailure];
      return;
    }
    if (successBlock) {
      successBlock(transport);
    }
  });
}

#pragma mark Raporting

- (void)reportStartupProgress:(NSString *)progress withTimeoutInterval:(NSTimeInterval)interval
{
  NSAssert([NSThread isMainThread], @"code should be running on main thread");
  if (!self.testPlanDidStartExecuting) {
    [self logTestManagerMessage:@"%@, will wait up to %gs", progress, interval];
    [self.startupTimeoutTimer invalidate];
    self.startupTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(startupTimedOut:) userInfo:@{@"description" : progress} repeats:NO];
  }
}

- (void)startupTimedOut:(NSTimer *)timer
{
  [self reportStartupFailure:[NSString stringWithFormat:@"Canceling tests due to timeout in %@", timer.userInfo[@"description"]] errorCode:FBErrorCodeStartupFailure];
}

- (void)reportStartupFailure:(NSString *)failure errorCode:(NSInteger)errorCode
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.finished && !self.hasFailed) {
      self.hasFailed = YES;
      self.finished = YES;
      [self logTestManagerMessage:@"Test operation failure: %@", failure];
      [self.startupTimeoutTimer invalidate];
      [self finishWithError:[NSError errorWithDomain:@"IDETestOperationsObserverErrorDomain" code:errorCode userInfo:@{NSLocalizedDescriptionKey : failure ?: @"Mystery"}] didCancel:YES];
    }
  });
}


- (void)finishWithError:(NSError *)error didCancel:(BOOL)didCancel
{
  [self logTestManagerMessage:@"_finishWithError:%@ didCancel: %d", error, didCancel];
  if (self.testingIsFinished) {
    [self logTestManagerMessage:@"Testing has already finished, ignoring this report."];
    return;
  }
  self.finished = YES;
  self.testingIsFinished = YES;

  if (getenv("XCS")) {
    [self __finishXCS];
    return;
  }

  [self detect_r17733855_fromError:error];
  if (error) {
    NSString *message = @"";
    NSMutableDictionary *userInfo = error.userInfo.mutableCopy;
    if(error.localizedRecoverySuggestion){
      message = error.localizedRecoverySuggestion;
      userInfo[NSLocalizedRecoverySuggestionErrorKey] = message;
    } else if (error.localizedDescription) {
      message = error.localizedDescription;
      userInfo[NSLocalizedDescriptionKey] = message;
    } else if (error.localizedFailureReason) {
      message = error.localizedFailureReason;
      userInfo[NSLocalizedFailureReasonErrorKey] = message;
    }
    error = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
    if (error.code != FBErrorCodeLostConnection) {
      [self logTestManagerMessage:@"\n\n*** %@\n\n", message];
    }
  }
}

#pragma mark Others

- (void)logTestManagerMessage:(NSString *)format, ...
{
  // Possibly we should push that to test dashboard
  va_list arguments;
  va_start(arguments, format);
  NSLogv(format, arguments);
}

- (void)detect_r17733855_fromError:(NSError *)error
{
  if (!self.targetIsiOSSimulator) {
    return;
  }
  if (!error) {
    return;
  }
  NSString *message = error.localizedDescription;
  if ([message rangeOfString:@"Unable to run app in Simulator"].location != NSNotFound || [message rangeOfString:@"Test session exited(-1) without checking in"].location != NSNotFound ) {
    [self logTestManagerMessage:@"Detected radar issue r17733855"];
  }
}

#pragma mark - XCTestManager_IDEInterface protocol

- (id)_XCT_launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment
{
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

- (id)_XCT_getProgressForLaunch:(id)token
{
  [self logTestManagerMessage:@"Test process requested launch process status with token %@", token];
  DTXRemoteInvocationReceipt *recepit = [DTXRemoteInvocationReceipt new];
  [recepit invokeCompletionWithReturnValue:@1 error:nil];
  return recepit;
}

- (id)_XCT_testSuite:(NSString *)tests didStartAt:(NSString *)time
{
  [self logTestManagerMessage:@"_XCT_testSuite:%@ didStartAt:%@", tests, time];
  if (tests.length == 0) {
    [self logTestManagerMessage:@"Failing for nil suite identifier."];
    NSError *error = [NSError errorWithDomain:@"IDETestOperationsObserverErrorDomain" code:0x9 userInfo:@{NSLocalizedDescriptionKey : @"Test reported a suite with nil or empty identifier. This is unsupported."}];
    [self finishWithError:error didCancel:NO];
  }
  return nil;
}

- (id)_XCT_didBeginExecutingTestPlan
{
  self.testPlanDidStartExecuting = YES;
  [self logTestManagerMessage:@"Starting test plan, clearing initialization timeout timer."];
  [self.startupTimeoutTimer invalidate];
  return nil;
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  [self.startupTimeoutTimer invalidate];
  NSInteger protocolVersionInt = protocolVersion.integerValue;
  NSInteger minimumVersionInt = minimumVersion.integerValue;

  self.testBundleProtocolVersion = protocolVersionInt;

  [self logTestManagerMessage:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion];
  if (minimumVersionInt > FBProtocolVersion) {
    [self reportStartupFailure:[NSString stringWithFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion] errorCode:FBErrorCodeStartupFailure];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    [self reportStartupFailure:[NSString stringWithFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion,protocolVersionInt] errorCode:FBErrorCodeStartupFailure];
    return nil;
  }
  if (self.targetDevice.requiresTestDaemonMediationForTestHostConnection) {
    [self whitelistTestProcessIDForUITesting];
    return nil;
  }
  [self _checkUITestingPermissionsForPID:self.testRunnerPID];
  return nil;
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self logTestManagerMessage:@"_XCT_testCaseDidStartForTestClass:%@ method:%@", testClass, method ?: @""];
  return nil;
}

// This looks like tested application logs
- (id)_XCT_logDebugMessage:(NSString *)debugMessage
{
  return nil;
}

// ?
- (id)_XCT_logMessage:(NSString *)message
{
  [self logTestManagerMessage:@"MAGIC_MESSAGE: %@", message];
  return nil;
}


#pragma mark - Unimplemented

- (NSString *)unknownMessageForSelector:(SEL)aSelector
{
  return [NSString stringWithFormat:@"Received call for unhandled method (%@). Probably you should have a look at _IDETestManagerAPIMediator in IDEFoundation.framework and implement it. Good luck!", NSStringFromSelector(aSelector)];
}

// This will add more logs when unimplemented method from XCTestManager_IDEInterface protocol is called
- (id)forwardingTargetForSelector:(SEL)aSelector
{
  NSLog(@"%@", [self unknownMessageForSelector:aSelector]);
  return nil;
}

// This method name reflects method in _IDETestManagerAPIMediator
- (void)_checkUITestingPermissionsForPID:(int)pid
{
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
}


#pragma mark - Unsupported partly disassembled

- (void)__beginSessionWithBundlePath:(NSString *)bundlePath remoteProxy:(id<XCTestManager_DaemonConnectionInterface>)remoteProxy proxyChannel:(DTXProxyChannel *)proxyChannel
{
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
  DTXRemoteInvocationReceipt *receipt = [remoteProxy _IDE_beginSessionWithIdentifier:self.sessionIdentifier
                                                                                       forClient:self.class.clientProcessUniqueIdentifier
                                                                                          atPath:bundlePath];
  weakify(self);
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    strongify(self);
    if (!self) {
      [self logTestManagerMessage:@"(strongSelf) should not be nil"];
      return;
    }
    [self finilzeConnectionWithProxyChannel:proxyChannel error:error];
  }];
}

- (void)__finishXCS
{
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
  [self.targetDevice _syncDeviceCrashLogsDirectoryWithCompletionHandler:^(NSError *crashLogsSyncError){
    dispatch_async(dispatch_get_main_queue(), ^{
      CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
      if (crashLogsSyncError) {
        [self logTestManagerMessage:@"Error syncing device diagnostic logs after %.1fs: %@", time, crashLogsSyncError];
      }
      else {
        [self logTestManagerMessage:@"Finished syncing device diagnostic logs after %.1fs.", time];
      }
    });
  }];
}

@end
