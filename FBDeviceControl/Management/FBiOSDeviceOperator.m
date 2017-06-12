/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSDeviceOperator.h"

#import <objc/runtime.h>

#import <DTDeviceKitBase/DTDKRemoteDeviceConsoleController.h>
#import <DTDeviceKitBase/DTDKRemoteDeviceToken.h>

#import <DTXConnectionServices/DTXChannel.h>
#import <DTXConnectionServices/DTXMessage.h>
#import <DTXConnectionServices/DTXSocketTransport.h>

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTFuture.h>

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <objc/runtime.h>

#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"

@protocol DVTApplication <NSObject>
- (NSString *)installedPath;
- (NSString *)containerPath;
- (NSString *)identifier;
- (NSString *)executableName;
@end

static NSString *const ApplicationNameKey = @"CFBundleName";
static NSString *const ApplicationIdentifierKey = @"CFBundleIdentifier";
static NSString *const ApplicationTypeKey = @"ApplicationType";
static NSString *const ApplicationPathKey = @"Path";

@interface FBiOSDeviceOperator ()

@property (nonatomic, strong, readonly) FBDevice *device;

@end

@implementation FBiOSDeviceOperator

+ (instancetype)forDevice:(FBDevice *)device
{
  return [[self alloc] initWithDevice:device];
}

- (instancetype)initWithDevice:(FBDevice *)device;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

- (NSString *)udid
{
  return self.device.udid;
}

#pragma mark - Device specific operations

- (NSString *)containerPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  id<DVTApplication> app = [self installedApplicationWithBundleIdentifier:bundleID];
  return [app containerPath];
}

- (NSString *)applicationPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  id<DVTApplication> app = [self installedApplicationWithBundleIdentifier:bundleID];
  return [app installedPath];
}

- (void)fetchApplications
{
  if (!self.device.dvtDevice.applications) {
    [FBRunLoopSpinner spinUntilBlockFinished:^id{
      DVTFuture *future = self.device.dvtDevice.token.fetchApplications;
      [future waitUntilFinished];
      return nil;
    }];
  }
}

- (id<DVTApplication>)installedApplicationWithBundleIdentifier:(NSString *)bundleID
{
  [self fetchApplications];
  return [self.device.dvtDevice installedApplicationWithBundleIdentifier:bundleID];
}

- (FBProductBundle *)applicationBundleWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  id<DVTApplication> application = [self installedApplicationWithBundleIdentifier:bundleID];
  if (!application) {
    return nil;
  }

  FBProductBundle *productBundle =
  [[[[[FBProductBundleBuilder builder]
      withBundlePath:[application installedPath]]
     withBundleID:[application identifier]]
    withBinaryName:[application executableName]]
   buildWithError:error];

  return productBundle;
}

- (BOOL)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID error:(NSError **)error
{
  __block NSError *innerError = nil;
  BOOL result = [[FBRunLoopSpinner spinUntilBlockFinished:^id{
    return @([self.device.dvtDevice uploadApplicationDataWithPath:path forInstalledApplicationWithBundleIdentifier:bundleID error:&innerError]);
  }] boolValue];
  *error = innerError;
  return result;
}

- (BOOL)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error
{
  id returnObject =
  [FBRunLoopSpinner spinUntilBlockFinished:^id{
    if ([self.device.dvtDevice installedApplicationWithBundleIdentifier:bundleIdentifier]) {
      return [self.device.dvtDevice uninstallApplicationWithBundleIdentifierSync:bundleIdentifier];
    }
    return nil;
  }];
  if ([returnObject isKindOfClass:NSError.class]) {
    if (error != nil) {
      *error = returnObject;
    }
    return NO;
  }
  return YES;
}


#pragma mark - FBDeviceOperator protocol

- (DTXTransport *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if ([NSThread isMainThread]) {
    return
    [[[FBDeviceControlError
       describe:@"'makeTransportForTestManagerService' method may block and should not be called on the main thread"]
      logger:logger]
     fail:error];
  }
  NSError *innerError;
  CFTypeRef connection = [self.device.amDevice startTestManagerServiceWithError:&innerError];
  if (!connection) {
    return
    [[[[FBDeviceControlError
        describe:@"Failed to start test manager daemon service."]
       logger:logger]
      causedBy:innerError]
     fail:error];
  }
  int socket = FBAMDServiceConnectionGetSocket(connection);
  if (socket <= 0) {
    return
    [[[FBDeviceControlError
       describe:@"Invalid socket returned from AMDServiceConnectionGetSocket"]
      logger:logger]
     fail:error];
  }
  return
  [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket disconnectAction:^{
    [logger log:@"Disconnected from test manager daemon socket"];
    FBAMDServiceConnectionInvalidate(connection);
  }];
}

- (BOOL)requiresTestDaemonMediationForTestHostConnection
{
  return self.device.dvtDevice.requiresTestDaemonMediationForTestHostConnection;
}

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError **)error
{
  if (![[[[[FBRunLoopSpinner new]
           timeout:5 * 60]
          timeoutErrorMessage:@"Device was locked"]
         reminderMessage:@"Please unlock device!"]
        spinUntilTrue:^BOOL{ return ![self.device.dvtDevice isPasscodeLocked]; } error:error])
  {
    return NO;
  }

  if (![[[[[FBRunLoopSpinner new]
           timeout:5 * 60]
          timeoutErrorMessage:@"Device did not become available"]
         reminderMessage:@"Waiting for device to become available!"]
        spinUntilTrue:^BOOL{ return [self.device.dvtDevice isAvailable]; }])
  {
    return NO;
  }

  if (![[[[[FBRunLoopSpinner new]
           timeout:5 * 60]
          timeoutErrorMessage:@"Failed to gain access to device"]
         reminderMessage:@"Allow device access!"]
        spinUntilTrue:^BOOL{ return [self.device.dvtDevice deviceReady]; } error:error])
  {
    return NO;
  }

  __block NSUInteger preLaunchLogLength;
  __block NSString *preLaunchConsoleString;
  if (![[[[FBRunLoopSpinner new]
          timeout:60]
         timeoutErrorMessage:@"Failed to load device console entries"]
        spinUntilTrue:^BOOL{
          NSString *log = self.consoleString.copy;
          if (log.length == 0) {
            return NO;
          }
          // Waiting for console to load all entries
          if (log.length != preLaunchLogLength) {
            preLaunchLogLength = log.length;
            return NO;
          }
          preLaunchConsoleString = log;
          return YES;
        } error:error])
  {
    return NO;
  }

  if (!self.device.dvtDevice.supportsXPCServiceDebugging) {
    return [[FBDeviceControlError
      describe:@"Device does not support XPC service debugging"]
      failBool:error];
  }

  if (!self.device.dvtDevice.serviceHubProcessControlChannel) {
    return [[FBDeviceControlError
      describe:@"Failed to create HUB control channel"]
      failBool:error];
  }
  return YES;
}

- (pid_t)processIDWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  return
  [[self executeHubProcessControlSelector:NSSelectorFromString(@"processIdentifierForBundleIdentifier:")
                                    error:error
                                arguments:bundleID, nil]
   intValue];
}

- (nullable FBDiagnostic *)attemptToFindCrashLogForProcess:(pid_t)pid bundleID:(NSString *)bundleID
{
  return nil;
}

- (NSString *)consoleString
{
  return [self.device.dvtDevice.token.deviceConsoleController consoleString];
}

- (BOOL)observeProcessWithID:(NSInteger)processID error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  [self executeHubProcessControlSelector:NSSelectorFromString(@"startObservingPid:")
                                   error:error
                               arguments:@(processID), nil];
  return (*error == nil);
}

- (BOOL)killProcessWithID:(NSInteger)processID error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  [self executeHubProcessControlSelector:NSSelectorFromString(@"killPid:")
                                   error:error
                               arguments:@(processID), nil];
  return (*error == nil);
}

- (NSArray<NSDictionary<NSString *, id> *> *)installedApplicationsData
{
  [self fetchApplications];

  NSMutableArray *applications = [[NSMutableArray alloc] init];

  for(NSObject *app in self.device.dvtDevice.applications) {
    NSDictionary *dict = [app valueForKey:@"plist"];
    if (!dict) {
      continue;
    }
    [applications addObject:dict];
  }
  return applications;
}

#pragma mark FBApplicationCommands Implementation

- (id)handleWithAFCSession:(id(^)(void))operationBlock error:(NSError **)error
{
  __block NSError *innerError = nil;
  id result = [self.device.amDevice handleWithBlockDeviceSession:^(CFTypeRef device) {
    int afcConn;
    int afcReturnCode = FBAMDeviceSecureStartService(device, CFSTR("com.apple.afc"), NULL, &afcConn);
    if (afcReturnCode != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Failed to start afc service with error code: %x", afcReturnCode]
        fail:&innerError];
    }
    id operationResult = operationBlock();
    close(afcConn);
    return operationResult;
  } error: error];
  *error = innerError;
  return result;
}

- (BOOL)transferAppURL:(NSURL *)app_url options:(NSDictionary *)options error:(NSError **)error
{
  id transferReturnCode = [self handleWithAFCSession:^id() {
    return @(FBAMDeviceSecureTransferPath(0,
                                          self.device.amDevice.amDevice,
                                          (__bridge CFURLRef _Nonnull)(app_url),
                                          (__bridge CFDictionaryRef _Nonnull)(options),
                                          NULL,
                                          0));
  } error:error];

  if (transferReturnCode == nil) {
    return [[FBDeviceControlError
             describe:@"Failed to transfer path"]
            failBool:error];
  }

  if ([transferReturnCode intValue] != 0) {
    return [[FBDeviceControlError
             describeFormat:@"Failed to transfer path with error code: %x", [transferReturnCode intValue]]
            failBool:error];
  }
  return YES;
}

- (BOOL)secureInstallApplication:(NSURL *)app_url options:(NSDictionary *)options error:(NSError **)error
{
  NSNumber *install_return_code = [self.device.amDevice handleWithBlockDeviceSession:^id(CFTypeRef device) {
    return @(FBAMDeviceSecureInstallApplication(0, device, (__bridge CFURLRef _Nonnull)(app_url), (__bridge CFDictionaryRef _Nonnull)(options), NULL, 0));
  } error: error];

  if (install_return_code == nil) {
    return
    [[FBDeviceControlError
      describe:@"Failed to install application"]
     failBool:error];
  }
  if ([install_return_code intValue] != 0) {
    return
    [[FBDeviceControlError
      describe:@"Failed to install application"]
     failBool:error];
  }
  return YES;
}

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  NSURL *app_url = [NSURL fileURLWithPath:path isDirectory:YES];
  NSDictionary *options = @{@"PackageType" : @"Developer"};
  NSError *inner_error = nil;
  if (![self transferAppURL:app_url options:options error:&inner_error] ||
      ![self secureInstallApplication:app_url options:options error:&inner_error])
  {
    return [[[FBDeviceControlError
              describeFormat:@"Failed to install application with path %@", path]
             causedBy:inner_error]
            failBool:error];
  }

  return YES;
}

- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSError *innerError = nil;
  NSNumber *returnCode = [self.device.amDevice handleWithBlockDeviceSession:^id(CFTypeRef device) {
    return @(FBAMDeviceSecureUninstallApplication(0, device, (__bridge CFStringRef _Nonnull)(bundleID), 0, NULL, 0));
  } error: &innerError];

  if (returnCode == nil) {
    return
    [[[FBDeviceControlError
       describe:@"Failed to uninstall application"]
      causedBy:innerError]
     failBool:error];
  }
  if ([returnCode intValue] != 0) {
    return
    [[[FBDeviceControlError
       describeFormat:@"Failed to uninstall application with error code %x", [returnCode intValue]]
      causedBy:innerError]
     failBool:error];
  }
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self installedApplicationWithBundleIdentifier:bundleID] != nil;
}

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration error:(NSError **)error
{
  NSAssert(error, @"error is required for hub commands");
  NSString *remotePath = [self applicationPathForApplicationWithBundleID:configuration.bundleID error:error];
  NSDictionary *options = @{@"StartSuspendedKey" : @NO};
  SEL aSelector = NSSelectorFromString(@"launchSuspendedProcessWithDevicePath:bundleIdentifier:environment:arguments:options:");
  NSNumber *PID =
  [self executeHubProcessControlSelector:aSelector
                                   error:error
                               arguments:remotePath, configuration.bundleID, configuration.environment, configuration.arguments, options, nil];
  if (!PID) {
    return NO;
  }
  __block NSError *innerError = nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self observeProcessWithID:PID.integerValue error:&innerError];
  });
  *error = innerError;
  return YES;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  pid_t PID = [self processIDWithBundleID:bundleID error:error];
  if (PID < 1) {
    return NO;
  }
  return [self killProcessWithID:PID error:error];
}

- (NSArray<FBApplicationDescriptor *> *)installedApplications
{
  NSMutableArray<FBApplicationDescriptor *> *installedApplications = [[NSMutableArray alloc] init];

  for(NSDictionary *app in [self installedApplicationsData]) {
    if (app == nil) {
      continue;
    }
    FBApplicationDescriptor *appData = [FBApplicationDescriptor
      remoteApplicationWithName:app[ApplicationNameKey]
      path:app[ApplicationPathKey]
      bundleID:app[ApplicationIdentifierKey]];

    [installedApplications addObject:appData];
  }

  return [installedApplications copy];
}

#pragma mark - Helpers

- (id)executeHubProcessControlSelector:(SEL)aSelector error:(NSError **)error arguments:(id)arg, ...
{
  NSAssert(error, @"error is required for hub commands");
  va_list _arguments;
  va_start(_arguments, arg);
  va_list *arguments = &_arguments;

  __block NSError *innerError = nil;
  id result = [FBRunLoopSpinner spinUntilBlockFinished:^id{
    __block id responseObject;

    DTXChannel *channel = self.device.dvtDevice.serviceHubProcessControlChannel;
    DTXMessage *message = [[objc_lookUpClass("DTXMessage") alloc] initWithSelector:aSelector firstArg:arg remainingObjectArgs:(__bridge id)(*arguments)];
    [channel sendControlSync:message replyHandler:^(DTXMessage *responseMessage){
      if (responseMessage.errorStatus) {
        innerError = responseMessage.error;
        return;
      }
      responseObject = responseMessage.object;
    }];
    return responseObject;
  }];
  va_end(_arguments);
  *error = innerError;
  return result;
}

@end
