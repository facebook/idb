/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDLDevice.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBDeviceControlError.h"

#pragma mark Notifications

typedef NSString *FB_DLDeviceNotificationName NS_STRING_ENUM;

FB_DLDeviceNotificationName const FB_DLDeviceNotificationNameAttached = @"FB_DLDeviceNotificationNameAttached";
FB_DLDeviceNotificationName const FB_DLDeviceNotificationNameDetached = @"FB_DLDeviceNotificationNameDetached";

typedef NSString *FB_DLDeviceNotificationUserInfoKey NS_STRING_ENUM;

FB_DLDeviceNotificationUserInfoKey const FB_DLDeviceNotificationUserInfoKeyDLDevice = @"FB_DLDeviceNotificationUserInfoKeyDLDevice";

#pragma mark DeviceLink Structures

/**
 Derived from DLDeviceListenerSet* functions.
 Has a size of 0x38/56.
 */
typedef struct {
  void *attachedCallback; // 0x0
  void *detachedCallback; // 0x8
  void *stoppedCallback; // 0x10
  void *context; // 0x18
  void *unknown0; // 0x20
  CFArrayRef callbackArray; // 0x28
  void *unknown1; // 0x30
} DLDeviceListener;

/**
 Derived from DLDeviceGet* functions.
 Has a size of 0x20/32
 */
typedef struct {
  CFDictionaryRef info; // 0x0
  CFArrayRef endpoints; // 0x8
  CFTypeRef amDevice; // 0x10
  void *unknown0; // 0x18
} DLDevice;

/**
 Derived from DLCreateDeviceLinkConnection.
 */
typedef struct {
  void *incomingConnectionCallback; // 0x0
  void *connectionMadeCallback; // 0x8
  void *connectionFailedCallback; // 0x10
  void *acceptFailedCallback; // 0x18
  void *disconnectCallback; // 0x20
  void *connectionLostCallback; // 0x28
  void *processMessageCallback; // 0x30
  void *pingCallback; // 0x38
  void *requestFileCallback; // 0x40
  void *sendFileCallback; // 0x48
  void *context; // 0x50. This value is not set so is assumed to be a context pointer
  void *deviceReadyCallback; // 0x58
  intptr_t padding[14]; // 0x60 - 0xd0
} DLDeviceConnectionCallbacks;

/**
 Derived from DLDeviceConnection functions.
 Has a combined size of 208/0xd0.
 */
typedef struct {
  void *padding0[5]; // 0x0 - 0x20
  DLDeviceConnectionCallbacks *callbacks; // 0x28
  void *padding1[3]; // 0x30 - 0x40
  CFStringRef name; // 0x48
  CFMessagePortRef receivePort; // 0x50
  void *padding3; // 0x58
  CFMessagePortRef sendPort; // 0x60
  void *unknown12; // 0x68
  void *unknown13; // 0x70
  void *unknown14; // 0x78
  void *condition; // 0x80
  void *unknown17; // 0x88
  void *unknown18; // 0x90
  void *unknown19; // 0x98
  CFNumberRef number0; // 0xa0
  CFNumberRef number1; // 0xa8
  void *unknown20; // 0xb0
  void *unknown21; // 0xb8
  void *unknown22; // 0xc0
  void *unknown23; // 0xc8
} DLDeviceConnection;

#pragma mark DeviceLink APIs

// Management
void * (*FB_DLCopyConnectedDeviceArray)(DLDeviceListener *deviceListener);
DLDeviceListener * (*FB_DLDeviceListenerCreateWithCallbacks)(void *deviceAttachedCallback, void *deviceDetachedCallback, void *deviceListenerStoppedCallback, void *context);
void * (*FB_DLDeviceWaitForAttachedDevice)(DLDeviceListener *deviceListener, CFStringRef udid);

// Getters
NSString * (*FB_DLDeviceCreateDescription)(DLDevice *device, DLDeviceListener *deviceListener);
NSString * (*FB_DLDeviceGetUDID)(DLDevice *device);
void * (*FB_DLDeviceGetWithUDID)(DLDeviceListener *deviceListener, CFStringRef udid);

// Setters
void *(*FB_DLDeviceListenerSetContext)(DLDeviceListener *listener, void *context);

// Connections
int (*FB_DLCreateDeviceLinkConnectionForComputer)(int arg0, DLDeviceConnectionCallbacks *callback, int arg2, DLDeviceConnection **connectionOut, CFStringRef *errorDescriptionOut);
int (*FB_DLConnectToServiceOnDevice)(DLDeviceConnection *connection, DLDevice *device, CFStringRef serviceName, CFStringRef *errorDescriptionOut);
int (*FB_DLProcessMessage)(DLDeviceConnection *connection, CFDictionaryRef requestDictionary, CFStringRef *errorDescriptionOut);
int (*FB_DLDisconnect)(DLDeviceConnection *connection, CFStringRef message, CFStringRef *errorDescriptionOut);

// Memory Management
void *(*FB_DLDeviceRetain)(DLDevice *device);
void  (*FB_DLDeviceRelease)(DLDevice *device);

#pragma mark Objective-C Interfaces

@interface FBDLDeviceConnection_Context : NSObject

@property (nonatomic, strong, readonly) FBMutableFuture<NSDictionary<NSString *, id> *> *completion;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *request;
@property (nonatomic, copy, readonly) NSString *serviceName;

@end

@interface FBDLDeviceManager : NSObject

@property (nonatomic, assign, readonly) DLDeviceListener *listener;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBDLDevice *> *currentDevices;
@property (nonatomic, strong, readonly) NSMapTable *connectionToDevice;

+ (instancetype)sharedManager;
- (void)deviceAttached:(DLDevice *)dlDevice logger:(id<FBControlCoreLogger>)logger;
- (void)deviceDetached:(DLDevice *)dlDevice;

@end

@interface FBDLDevice ()

@property (nonatomic, weak, readonly) FBDLDeviceManager *manager;
@property (nonatomic, assign, readonly) DLDevice *dlDevice;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, assign, readwrite) DLDeviceConnection *connection;
@property (nonatomic, strong, readwrite) FBDLDeviceConnection_Context *connectionContext;

- (instancetype)initWithDLDevice:(DLDevice *)dlDevice manager:(FBDLDeviceManager *)manager queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBDLDeviceConnection_Context

- (instancetype)initWithCompletion:(FBMutableFuture<NSDictionary<NSString *, id> *> *)completion request:(NSDictionary<NSString *, id> *)request serviceName:(NSString *)serviceName
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _completion = completion;
  _request = request;
  _serviceName = serviceName;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@ %@", self.serviceName, [FBCollectionInformation oneLineDescriptionFromDictionary:self.request]];
}

@end

#pragma mark Connection/Device Lifecycle

static FBDLDevice *FB_DLDeviceConnectionGetDevice(DLDeviceConnection *connection)
{
  FBDLDeviceManager *manager = (__bridge FBDLDeviceManager *)(connection->callbacks->context);
  FBDLDevice *device = (__bridge FBDLDevice *) NSMapGet(manager.connectionToDevice, connection);
  return device;
}

static void FB_DLDeviceConnectionSetDevice(DLDeviceConnection *connection, FBDLDevice *device)
{
  FBDLDeviceManager *listener = (__bridge FBDLDeviceManager *)(connection->callbacks->context);
  NSMapTable *connectionToDevice = listener.connectionToDevice;
  FBDLDevice *currentDevice = (__bridge FBDLDevice *) NSMapGet(connectionToDevice, (__bridge const void *_Nullable)(listener));

  if (currentDevice) {
    NSCAssert(device == NULL, @"Cannot change the device for a connection.");
    NSMapRemove(connectionToDevice, connection);
  } else {
    NSCAssert(device != NULL, @"Removing the device for a connection requires an existing device.");
    NSMapInsert(connectionToDevice, connection, (__bridge const void *_Nullable)(device));
  }
}

static void FB_DLDeviceConnectionCallbacksDestroy(DLDeviceConnectionCallbacks *callbacks)
{
  free(callbacks);
}

static void FB_DLDeviceConnectionDestroy(DLDeviceConnection *connection)
{
  FBDLDevice *context = FB_DLDeviceConnectionGetDevice(connection);
  [context.logger log:@"Disconnecting from Connection"];
  CFStringRef errorDescription = nil;
  int code = FB_DLDisconnect(connection, (__bridge CFStringRef) @"Done", &errorDescription);
  if (code != 0) {
    [context.logger logFormat:@"Disconnect Failed %d: %@", code, errorDescription];
  }
  FB_DLDeviceConnectionCallbacksDestroy(connection->callbacks);
}

static NSString *FB_DLDeviceConnectionDescribe(DLDeviceConnection *connection)
{
  return [NSString stringWithFormat:@"Connection %@", CFMessagePortGetName(connection->receivePort)];
}

static FBDLDeviceManager *FB_DLDeviceListenerGetManager(DLDeviceListener *listener)
{
  return (__bridge FBDLDeviceManager *) listener->context;
}

#pragma mark Callbacks

static void FB_DeviceAttachedCallback(DLDeviceListener *deviceListener, DLDevice *device, void *context)
{
  FBDLDeviceManager *manager = FB_DLDeviceListenerGetManager(deviceListener);
  [manager deviceAttached:device logger:manager.logger];
}

static void FB_DeviceDetachedCallback(DLDeviceListener *deviceListener, DLDevice *device, void *context)
{
  FBDLDeviceManager *manager = FB_DLDeviceListenerGetManager(deviceListener);
  [manager deviceDetached:device];
}

static void FB_DeviceReadyCallback(DLDeviceConnection *connection)
{
  FBDLDevice *device = FB_DLDeviceConnectionGetDevice(connection);
  FBDLDeviceConnection_Context *context = device.connectionContext;
  if (!context) {
    [device.logger logFormat:@"No active request for device %@.", device];
    return;
  }
  CFStringRef errorDescription = nil;
  int status = FB_DLProcessMessage(connection, (__bridge CFDictionaryRef) device.connectionContext.request, &errorDescription);
  [device.logger logFormat:@"Processed Message %@ with status %d", context, status];
  if (status != 0) {
    NSError *error = [[FBDeviceControlError describeFormat:@"Process Messsage Failed with %d: %@.", status, errorDescription] build];
    [device.connectionContext.completion resolveWithError:error];
    FB_DLDeviceConnectionDestroy(connection);
  }
}

static void FB_ProcessMessageCallback(DLDeviceConnection *connection, NSDictionary<NSString *, id> *message)
{
  FBDLDevice *device = FB_DLDeviceConnectionGetDevice(connection);
  [device.connectionContext.completion resolveWithResult:message];
  [device.logger logFormat:@"Callback for %@. Considering it done.", device.connectionContext];
  device.connectionContext = nil;
}

#pragma mark Connection Context

static DLDeviceConnectionCallbacks *FB_DLDeviceConnectionCallbacksCreate(FBDLDeviceManager *manager)
{
  DLDeviceConnectionCallbacks *callbacks = calloc(1, sizeof(DLDeviceConnectionCallbacks));
  callbacks->processMessageCallback = FB_ProcessMessageCallback;
  callbacks->deviceReadyCallback = FB_DeviceReadyCallback;
  callbacks->context = (__bridge void *)(manager);
  return callbacks;
}

@implementation FBDLDeviceManager

#pragma mark Framework Loading

+ (void)loadDLDeviceSymbols
{
  NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.apple.DeviceLinkX"];
  NSCAssert(bundle.loaded, @"DeviceLink is not loaded");
  NSString *path = [bundle.bundlePath stringByAppendingPathComponent:@"Versions/Current/DeviceLink"];
  void *handle = dlopen(path.UTF8String, RTLD_LAZY);

  FB_DLConnectToServiceOnDevice = FBGetSymbolFromHandle(handle, "DLConnectToServiceOnDevice");
  FB_DLCopyConnectedDeviceArray = FBGetSymbolFromHandle(handle, "DLCopyConnectedDeviceArray");
  FB_DLCreateDeviceLinkConnectionForComputer = FBGetSymbolFromHandle(handle, "DLCreateDeviceLinkConnectionForComputer");
  FB_DLDeviceCreateDescription = FBGetSymbolFromHandle(handle, "DLDeviceCreateDescription");
  FB_DLDeviceGetUDID = FBGetSymbolFromHandle(handle, "DLDeviceGetUDID");
  FB_DLDeviceGetWithUDID = FBGetSymbolFromHandle(handle, "DLDeviceGetWithUDID");
  FB_DLDeviceListenerCreateWithCallbacks = FBGetSymbolFromHandle(handle, "DLDeviceListenerCreateWithCallbacks");
  FB_DLDeviceListenerSetContext = FBGetSymbolFromHandle(handle, "DLDeviceListenerSetContext");
  FB_DLDeviceRelease = FBGetSymbolFromHandle(handle, "DLDeviceRelease");
  FB_DLDeviceRetain = FBGetSymbolFromHandle(handle, "DLDeviceRetain");
  FB_DLDeviceWaitForAttachedDevice = FBGetSymbolFromHandle(handle, "DLDeviceListenerCreateWithCallbacks");
  FB_DLDisconnect = FBGetSymbolFromHandle(handle, "DLDisconnect");
  FB_DLProcessMessage = FBGetSymbolFromHandle(handle, "DLProcessMessage");
}

+ (void)setDeviceLinkLogLevel:(int)logLevel
{
  // In the logging facility, logs are not written using os_log.
  // Instead they are written to ~/Library/Logs/DeviceLink/
  NSNumber *levelNumber = @(logLevel);
  CFPreferencesSetAppValue(CFSTR("LogLevel"), (__bridge CFPropertyListRef _Nullable)(levelNumber), CFSTR("com.apple.DeviceLink"));
}

#pragma mark Initializers

+ (instancetype)createDeviceManagerWithLogger:(id<FBControlCoreLogger>)logger
{
  // The context is initially empty and then set in DLDeviceListenerSetContext.
  DLDeviceListener *listener = FB_DLDeviceListenerCreateWithCallbacks(
    FB_DeviceAttachedCallback,
    FB_DeviceDetachedCallback,
    NULL,
    NULL
  );
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdevicecontrol.dldevice", DISPATCH_QUEUE_SERIAL);
  FBDLDeviceManager *manager = [[FBDLDeviceManager alloc] initWithListener:listener queue:queue logger:logger];
  FB_DLDeviceListenerSetContext(listener, (__bridge void *)(manager));
  return manager;
}

+ (instancetype)sharedManager
{
  static dispatch_once_t onceToken;
  static FBDLDeviceManager *manager;
  dispatch_once(&onceToken, ^{
    [FBDLDeviceManager setDeviceLinkLogLevel:10];
    [FBDLDeviceManager loadDLDeviceSymbols];
    id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
    manager = [FBDLDeviceManager createDeviceManagerWithLogger:logger];
  });
  return manager;
}

- (instancetype)initWithListener:(DLDeviceListener *)listener queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _listener = listener;
  _queue = queue;
  _logger = logger;
  _currentDevices = [NSMutableDictionary dictionary];
  _connectionToDevice = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaquePersonality valueOptions:NSPointerFunctionsStrongMemory];

  return self;
}

#pragma mark Device Management

- (void)deviceAttached:(DLDevice *)dlDevice logger:(id<FBControlCoreLogger>)logger
{
  logger = [logger withName:FB_DLDeviceGetUDID(dlDevice)];
  FBDLDevice *device = [[FBDLDevice alloc] initWithDLDevice:dlDevice manager:self queue:self.queue logger:logger];
  self.currentDevices[device.udid] = device;
  [NSNotificationCenter.defaultCenter postNotificationName:FB_DLDeviceNotificationNameAttached object:device.udid userInfo:@{
    FB_DLDeviceNotificationUserInfoKeyDLDevice: device,
  }];
  [self.logger logFormat:@"%@ Attached", device];
}

- (void)deviceDetached:(DLDevice *)dlDevice
{
  NSString *udid = FB_DLDeviceGetUDID(dlDevice);
  FBDLDevice *device = self.currentDevices[udid];
  if (!device) {
    [self.logger logFormat:@"Could not find existing device attachment for %@", udid];
    return;
  }
  [NSNotificationCenter.defaultCenter postNotificationName:FB_DLDeviceNotificationNameDetached object:udid userInfo:@{
    FB_DLDeviceNotificationUserInfoKeyDLDevice: device,
  }];
  [self.currentDevices removeObjectForKey:udid];
  [self.logger logFormat:@"%@ Detached", udid];
}

#pragma mark Connections

- (nullable DLDeviceConnection *)createConnectionForDevice:(DLDevice *)device error:(NSError **)error
{
  DLDeviceConnectionCallbacks *callbacks = FB_DLDeviceConnectionCallbacksCreate(self);

  DLDeviceConnection *connection = nil;
  CFStringRef errorDescription = nil;
  int code = FB_DLCreateDeviceLinkConnectionForComputer(0x1, callbacks, 0x0, &connection, &errorDescription);
  if (code != 0) {
    FB_DLDeviceConnectionCallbacksDestroy(callbacks);
    [[FBDeviceControlError
      describeFormat:@"Got Error %d: %@ from DLCreateDeviceLinkConnectionForComputer", code, errorDescription]
      fail:error];
    return NULL;
  }
  return connection;
}

- (FBFuture<NSDictionary<NSString *, id> *> *)onConnection:(DLDeviceConnection *)connection device:(FBDLDevice *)device service:(NSString *)serviceName performRequest:(NSDictionary<NSString *, id> *)request
{
  // Don't allow more than one request on the same connection.
  FBDLDeviceConnection_Context *context = FB_DLDeviceConnectionGetDevice(connection).connectionContext;
  if (context) {
    return [[FBDeviceControlError
      describeFormat:@"There is already an active request %@ on connection", context]
      failFuture];
  }

  // Start the connection, setting the context.
  CFStringRef errorDescription = nil;
  int code = FB_DLConnectToServiceOnDevice(connection, device.dlDevice, (__bridge CFStringRef) serviceName, &errorDescription);
  if (code != 0) {
    FB_DLDeviceConnectionDestroy(connection);
    return [[FBDeviceControlError
      describeFormat:@"Got Error %d: %@ from DLConnectToServiceOnDevice", code, errorDescription]
      failFuture];
  }
  FB_DLDeviceConnectionSetDevice(connection, device);

  // Update the context to the current request.
  FBMutableFuture<NSDictionary<NSString *, id> *> *completion = FBMutableFuture.future;
  device.connectionContext = [[FBDLDeviceConnection_Context alloc] initWithCompletion:completion request:request serviceName:serviceName];
  [self.logger logFormat:@"Started Request for %@", device.connectionContext];

  return completion;
}

@end

@implementation FBDLDevice

#pragma mark Initializers

+ (FBFuture<FBDLDevice *> *)deviceWithUDID:(NSString *)udid timeout:(NSTimeInterval)timeout
{
  FBDLDeviceManager *manager = FBDLDeviceManager.sharedManager;
  FBDLDevice *device = manager.currentDevices[udid];
  if (device) {
    return [FBFuture futureWithResult:device];
  }
  return [[FBDLDevice
    oneshotDeviceAttachedNotificationForUDID:udid onQueue:manager.queue]
    timeout:timeout waitingFor:@"the device %@ to appear", udid];
}

- (instancetype)initWithDLDevice:(DLDevice *)dlDevice manager:(FBDLDeviceManager *)manager queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  FB_DLDeviceRetain(dlDevice);
  _dlDevice = dlDevice;
  _manager = manager;
  _queue = queue;
  _udid = [FB_DLDeviceGetUDID(_dlDevice) copy];
  _logger = logger;

  return self;
}

#pragma mark NSObject

- (void)dealloc
{
  FB_DLDeviceRelease(_dlDevice);
  _dlDevice = nil;
}

- (NSString *)description
{
  return FB_DLDeviceCreateDescription(_dlDevice, self.manager.listener);
}

#pragma mark Public

- (FBFuture<NSDictionary<NSString *, id> *> *)onService:(NSString *)service performRequest:(NSDictionary<NSString *, id> *)request
{
  NSError *error = nil;
  DLDeviceConnection *connection = [self connectionWithError:&error];
  if (!connection) {
    return [FBFuture futureWithError:error];
  }
  return [self.manager onConnection:connection device:self service:service performRequest:request];
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
  connection = [self.manager createConnectionForDevice:self.dlDevice error:error];
  if (!connection) {
    [self.logger log:@"Error creating device connection"];
    return NULL;
  }
  FB_DLDeviceConnectionSetDevice(connection, self);
  self.connection = connection;
  [self.logger logFormat:@"Created Connection %@", FB_DLDeviceConnectionDescribe(connection)];
  return connection;
}

+ (FBFuture<FBDLDevice *> *)oneshotDeviceAttachedNotificationForUDID:(NSString *)udid onQueue:(dispatch_queue_t)queue
{
  __weak NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  FBMutableFuture<FBDLDevice *> *future = [FBMutableFuture future];

  id __block observer = [notificationCenter
    addObserverForName:FB_DLDeviceNotificationNameAttached
    object:nil
    queue:NSOperationQueue.mainQueue
    usingBlock:^(NSNotification *notification) {
      if (![notification.object isEqualToString:udid]) {
        return;
      }
      FBDLDevice *device = notification.userInfo[FB_DLDeviceNotificationUserInfoKeyDLDevice];
      [future resolveWithResult:device];
      [notificationCenter removeObserver:observer];
    }];

  return [future onQueue:queue respondToCancellation:^{
    [notificationCenter removeObserver:observer];
    return [FBFuture futureWithResult:NSNull.null];
  }];
}

@end
