/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDLDevice.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBDeviceControlError.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"
#import "FBDLDefines.h"

#pragma mark Objective-C Interfaces

@interface FBDLDeviceConnection_Context : NSObject

@property (nonatomic, strong, readonly) FBDLDevice *device;
@property (nonatomic, copy, readonly) NSString *serviceName;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *request;
@property (nonatomic, strong, readonly) FBMutableFuture<NSDictionary<NSString *, id> *> *completion;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@interface FBDLDevice ()

@property (nonatomic, assign, readonly) DLDevice *dlDevice;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, assign, readwrite) DLDeviceConnection *connection;

- (instancetype)initWithDLDevice:(DLDevice *)dlDevice queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

+ (DLDeviceCalls)defaultCalls;

@end

@implementation FBDLDeviceConnection_Context

- (instancetype)initWithDevice:(FBDLDevice *)device serviceName:(NSString *)serviceName request:(NSDictionary<NSString *, id> *)request completion:(FBMutableFuture<NSDictionary<NSString *, id> *> *)completion logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _serviceName = serviceName;
  _request = request;
  _completion = completion;
  _logger = logger;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@ %@", self.serviceName, [FBCollectionInformation oneLineDescriptionFromDictionary:self.request]];
}

@end

#pragma mark Connection/Device Lifecycle

static FBDLDeviceConnection_Context *FB_DLDeviceConnectionGetContext(DLDeviceConnection *connection)
{
  FBDLDeviceConnection_Context *context = (__bridge FBDLDeviceConnection_Context *) (connection->callbacks->context);
  return context;
}

static BOOL FB_DLDeviceConnectionSetContext(DLDeviceConnection *connection, FBDLDeviceConnection_Context *context)
{
  if (context) {
    if (connection->callbacks->context != NULL) {
      return NO;
    }
    connection->callbacks->context = (void *) CFBridgingRetain(context);
    return YES;
  } else {
    if (connection->callbacks->context != NULL) {
      CFTypeRef existing = connection->callbacks->context;
      connection->callbacks->context = NULL;
      CFRelease(existing);
    }
    connection->callbacks->context = NULL;
    return YES;
  }
}

static void FB_DLDeviceConnectionCallbacksDestroy(DLDeviceConnectionCallbacks *callbacks)
{
  free(callbacks);
}

static void FB_DLDeviceConnectionDestroy(DLDeviceConnection *connection)
{
  FBDLDeviceConnection_Context *context = FB_DLDeviceConnectionGetContext(connection);
  [context.logger log:@"Disconnecting from Connection"];
  CFStringRef errorDescription = nil;
  int code = FBDLDevice.defaultCalls.Disconnect(connection, (__bridge CFStringRef) @"Done", &errorDescription);
  if (code != 0) {
    [context.logger logFormat:@"Disconnect Failed %d: %@", code, errorDescription];
  }
  FB_DLDeviceConnectionCallbacksDestroy(connection->callbacks);
}

static NSString *FB_DLDeviceConnectionDescribe(DLDeviceConnection *connection)
{
  return [NSString stringWithFormat:@"Connection %@", CFMessagePortGetName(connection->receivePort)];
}

#pragma mark Callbacks

static void FB_DeviceReadyCallback(DLDeviceConnection *connection)
{
  FBDLDeviceConnection_Context *context = FB_DLDeviceConnectionGetContext(connection);
  CFStringRef errorDescription = nil;
  int status = FBDLDevice.defaultCalls.ProcessMessage(connection, (__bridge CFDictionaryRef) context.request, &errorDescription);
  [context.logger logFormat:@"Processed Message %@ with status %d", context, status];
  if (status != 0) {
    NSError *error = [[FBDeviceControlError describeFormat:@"Process Messsage Failed with %d: %@.", status, errorDescription] build];
    [context.completion resolveWithError:error];
    FB_DLDeviceConnectionDestroy(connection);
  }
}

static void FB_ProcessMessageCallback(DLDeviceConnection *connection, NSDictionary<NSString *, id> *message)
{
  FBDLDeviceConnection_Context *context = FB_DLDeviceConnectionGetContext(connection);
  [context.completion resolveWithResult:message];
  [context.logger logFormat:@"Callback for %@. Considering it done.", context.device];
  FB_DLDeviceConnectionSetContext(connection, NULL);
}

#pragma mark Connection Context

static DLDeviceConnectionCallbacks *FB_DLDeviceConnectionCallbacksCreate(void)
{
  DLDeviceConnectionCallbacks *callbacks = calloc(1, sizeof(DLDeviceConnectionCallbacks));
  callbacks->processMessageCallback = FB_ProcessMessageCallback;
  callbacks->deviceReadyCallback = FB_DeviceReadyCallback;
  callbacks->context = NULL;
  return callbacks;
}

@implementation FBDLDevice

#pragma mark Initializers

+ (FBDLDevice *)deviceWithAMDevice:(FBAMDevice *)amDevice
{
  // There's no API in DeviceLink for creating a DLDevice from an AMDevice.
  // However, it is quite simple and the implementation for this exists in _AMDeviceNotification in DeviceLink.framework
  // There are some values that are placed into the "info", but this is mostly to make identification easier.
  DLDevice *dlDevice = malloc(sizeof(DLDevice));
  dlDevice->info = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
  dlDevice->endpoints = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
  dlDevice->amDevice = amDevice.amDevice;

  return [[FBDLDevice alloc] initWithDLDevice:dlDevice queue:amDevice.workQueue logger:amDevice.logger];
}

- (instancetype)initWithDLDevice:(DLDevice *)dlDevice queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  FBDLDevice.defaultCalls.Retain(dlDevice);
  _dlDevice = dlDevice;
  _queue = queue;
  _udid = [FBDLDevice.defaultCalls.GetUDID(_dlDevice) copy];
  _logger = logger;

  return self;
}

#pragma mark NSObject

- (void)dealloc
{
  FBDLDevice.defaultCalls.Release(_dlDevice);
  _dlDevice = nil;
}

- (NSString *)description
{
  return FBDLDevice.defaultCalls.CreateDescription(_dlDevice, NULL);
}

#pragma mark Public

- (FBFuture<NSDictionary<NSString *, id> *> *)onService:(NSString *)service performRequest:(NSDictionary<NSString *, id> *)request
{
  NSError *error = nil;
  DLDeviceConnection *connection = [self connectionWithError:&error];
  if (!connection) {
    return [FBFuture futureWithError:error];
  }
  return [self onConnection:connection service:service performRequest:request];
}

static NSString *MessageTypeKey = @"MessageType";
static NSString *ScreenshotRequestMessageType = @"ScreenShotRequest";
static NSString *ScreenshotReplyMessageType = @"ScreenShotReply";

- (FBFuture<NSData *> *)screenshotData
{
  NSDictionary<NSString *, id> *request = @{
    MessageTypeKey: ScreenshotRequestMessageType,
  };
  return [[self
    onService:@"com.apple.mobile.screenshotr" performRequest:request]
    onQueue:self.queue fmap:^(NSDictionary<NSString *, id> *response) {
      NSString *messageType = response[MessageTypeKey];
      if (![messageType isEqualToString:ScreenshotReplyMessageType]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not %@", messageType, ScreenshotReplyMessageType]
          failFuture];
      }
      NSData *screenshotData = response[@"ScreenShotData"];
      if (![screenshotData isKindOfClass:NSData.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not NSData", screenshotData.class]
          failFuture];
      }
      return [FBFuture futureWithResult:screenshotData];
    }];
}

#pragma mark Private

- (DLDeviceConnection *)connectionWithError:(NSError **)error
{
  DLDeviceConnection *connection = self.connection;
  if (connection) {
    [self.logger logFormat:@"Re-Using Connection %@", FB_DLDeviceConnectionDescribe(connection)];
    return connection;
  }
  connection = [self createConnectionWithError:error];
  if (!connection) {
    [self.logger logFormat:@"Error creating device connection: %@", *error];
    return NULL;
  }
  self.connection = connection;
  [self.logger logFormat:@"Created Connection %@", FB_DLDeviceConnectionDescribe(connection)];
  return connection;
}

- (nullable DLDeviceConnection *)createConnectionWithError:(NSError **)error
{
  DLDeviceConnectionCallbacks *callbacks = FB_DLDeviceConnectionCallbacksCreate();

  DLDeviceConnection *connection = nil;
  CFStringRef errorDescription = nil;
  int code = FBDLDevice.defaultCalls.CreateDeviceLinkConnectionForComputer(0x1, callbacks, 0x0, &connection, &errorDescription);
  if (code != 0) {
    FB_DLDeviceConnectionCallbacksDestroy(callbacks);
    [[FBDeviceControlError
      describeFormat:@"Got Error %d: %@ from DLCreateDeviceLinkConnectionForComputer", code, errorDescription]
      fail:error];
    return NULL;
  }
  return connection;
}

- (FBFuture<NSDictionary<NSString *, id> *> *)onConnection:(DLDeviceConnection *)connection service:(NSString *)serviceName performRequest:(NSDictionary<NSString *, id> *)request
{
  // Don't allow more than one request on the same connection.
  FBDLDeviceConnection_Context *context = FB_DLDeviceConnectionGetContext(connection);
  if (context) {
    return [[FBDeviceControlError
      describeFormat:@"There is already an active request %@ on connection", context]
      failFuture];
  }

  // Set the context on the connection
  FBMutableFuture<NSDictionary<NSString *, id> *> *completion = FBMutableFuture.future;
  context = [[FBDLDeviceConnection_Context alloc] initWithDevice:self serviceName:serviceName request:request completion:completion logger:self.logger];
  if (!FB_DLDeviceConnectionSetContext(connection, context)) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to set context"]
      failFuture];
  }

  // Connect to the service
  CFStringRef errorDescription = nil;
  int code = FBDLDevice.defaultCalls.ConnectToServiceOnDevice(connection, self.dlDevice, (__bridge CFStringRef) serviceName, &errorDescription);
  if (code != 0) {
    FB_DLDeviceConnectionSetContext(connection, NULL);
    FB_DLDeviceConnectionDestroy(connection);
    return [[FBDeviceControlError
      describeFormat:@"Got Error %d: %@ from DLConnectToServiceOnDevice", code, errorDescription]
      failFuture];
  }

  // Update the context to the current request.
  [self.logger logFormat:@"Started Request for %@", context];

  return completion;
}

+ (DLDeviceCalls)defaultCalls
{
  static dispatch_once_t onceToken;
  static DLDeviceCalls defaultCalls;
  dispatch_once(&onceToken, ^{
    [self populateDeviceLinkSymbols:&defaultCalls];
  });
  return defaultCalls;
}

+ (void)populateDeviceLinkSymbols:(DLDeviceCalls *)calls
{
  void *handle = [[NSBundle bundleWithIdentifier:@"com.apple.DeviceLinkX"] dlopenExecutablePath];
  calls->ConnectToServiceOnDevice = FBGetSymbolFromHandle(handle, "DLConnectToServiceOnDevice");
  calls->CopyConnectedDeviceArray = FBGetSymbolFromHandle(handle, "DLCopyConnectedDeviceArray");
  calls->CreateDeviceLinkConnectionForComputer = FBGetSymbolFromHandle(handle, "DLCreateDeviceLinkConnectionForComputer");
  calls->CreateDescription = FBGetSymbolFromHandle(handle, "DLDeviceCreateDescription");
  calls->GetUDID = FBGetSymbolFromHandle(handle, "DLDeviceGetUDID");
  calls->GetWithUDID = FBGetSymbolFromHandle(handle, "DLDeviceGetWithUDID");
  calls->ListenerCreateWithCallbacks = FBGetSymbolFromHandle(handle, "DLDeviceListenerCreateWithCallbacks");
  calls->ListenerSetContext = FBGetSymbolFromHandle(handle, "DLDeviceListenerSetContext");
  calls->Release = FBGetSymbolFromHandle(handle, "DLDeviceRelease");
  calls->Retain = FBGetSymbolFromHandle(handle, "DLDeviceRetain");
  calls->Disconnect = FBGetSymbolFromHandle(handle, "DLDisconnect");
  calls->ProcessMessage = FBGetSymbolFromHandle(handle, "DLProcessMessage");
}

+ (void)setDeviceLinkLogLevel:(int)logLevel
{
  // In the logging facility, logs are not written using os_log.
  // Instead they are written to ~/Library/Logs/DeviceLink/
  NSNumber *levelNumber = @(logLevel);
  CFPreferencesSetAppValue(CFSTR("LogLevel"), (__bridge CFPropertyListRef _Nullable)(levelNumber), CFSTR("com.apple.DeviceLink"));
}

@end
