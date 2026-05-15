/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>
#import <FBDeviceControl/FBDeviceCommands.h>

@class FBAFCConnection;
@class FBAMDServiceConnection;
@class FBAMDeviceServiceManager;
@class FBDeviceType;
@class FBOSVersion;

/**
 An Object Wrapper for AMDevice.
 AMDevice is a Core Foundation Type in the MobileDevice.framework.
 Some important things that we've learned about AMDevice from experimentation and looking at other open source projects:
 - AMDevice sessions should be short-lived. They will timeout after 60 seconds causing subsequent usages (e.g. starting house_arrest service) to fail with:
   0xe800002d (Could not send a message to the device.)
 - The AMDevice session only needs to be open long enough to initiate the operation that requires the AMDevice object. It can be closed immediately after
   without waiting for the subsequent operation to finish. E.g. the right sequence of operations for using a service like com.apple.syslog_relay is:
     AMDeviceConnect
     AMDeviceStartSession
     AMDeviceSecureStartService(amdevice, "com.apple.syslog_relay")
     AMDeviceStopSession
     AMDeviceDisconnect
     // Do stuff with syslog service
     AMDServiceConnectionInvalidate
    Previously we were keeping the AMDevice session open for the duration of the service operation, which could hit the 60 second timeout for long operations,
    causing the next operation to use the AMDevice session to fail.
 - Only one AMDevice session should be open at once. Trying to open another will result in an error that the session is already active. To handle this we
   let concurrent operations share the AMDevice session and only close it when there are no waiting consumers.
   - Interestingly, trying to open a session a third time succeeds, so it seems the second attempt might kill off the first session
 - Starting / stopping the same service on the phone (e.g. house_arrest) many times in a short period will cause the error 0xe800005b (Too many instances of this service are already running.)
   Because of this, we pool service connections with a short cooldown to avoid reopening the same service repeatedly during bursts of operations using that service (e.g. recursively enumerating a directory)
 */
@interface FBAMDevice : NSObject <FBiOSTargetInfo, FBDeviceCommands, FBFutureContextManagerDelegate>

#pragma mark - FBiOSTargetInfo Protocol Members
// These are implemented in FBAMDevice.m but must be declared explicitly for Swift visibility
// since the FBiOSTargetInfo protocol is Swift-defined.
@property (nonnull, nonatomic, readonly, copy) NSString *uniqueIdentifier;
@property (nonnull, nonatomic, readonly, copy) NSString *udid;
@property (nonnull, nonatomic, readonly, copy) NSString *name;
@property (nonnull, nonatomic, readonly, strong) FBDeviceType *deviceType;
@property (nonnull, nonatomic, readonly, copy) NSArray<FBArchitecture> *architectures;
@property (nonnull, nonatomic, readonly, strong) FBOSVersion *osVersion;
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, id> *extendedInformation;
@property (nonatomic, readonly, assign) FBiOSTargetType targetType;
@property (nonatomic, readonly, assign) FBiOSTargetState state;

/**
 The queue on which work should be serialized.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t workQueue;

/**
 The queue on which asynchronous work can be performed sequentially.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t asyncQueue;

#pragma mark - Should be marked private when converting to Swift

/**
 The underyling AMDeviceRef.
 May be NULL.
 */
@property (nonatomic, readwrite, assign) AMDeviceRef _Nullable amDeviceRef;

/**
 All of the Device Values available.
 */
@property (nonnull, nonatomic, readwrite, copy) NSDictionary<NSString *, id> *allValues;

/**
 The Context Manager for the Connection
 */
@property (nonnull, nonatomic, readonly, strong) FBFutureContextManager<FBAMDevice *> *connectionContextManager;

/**
 The Service Manager.
 */
@property (nonnull, nonatomic, readonly, strong) FBAMDeviceServiceManager *serviceManager;

/**
 The Designated Initializer

 @param allValues the values from the AMDevice.
 @param calls the calls to use.
 @param connectionReuseTimeout the time to wait before releasing a connection
 @param serviceReuseTimeout the time to wait before releasing a service
 @param workQueue the queue on which work should be serialized.
 @param asyncQueue the queue on which asynchronous work can be performed sequentially.
 @param logger the logger to use.
 @return a new FBAMDevice instance.
 */
- (nonnull instancetype)initWithAllValues:(nonnull NSDictionary<NSString *, id> *)allValues calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout serviceReuseTimeout:(nullable NSNumber *)serviceReuseTimeout workQueue:(nonnull dispatch_queue_t)workQueue asyncQueue:(nonnull dispatch_queue_t)asyncQueue logger:(nonnull id<FBControlCoreLogger>)logger;

@end
