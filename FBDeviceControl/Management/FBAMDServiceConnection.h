/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@class FBServiceConnectionClient;

/**
 Abstract protocol for defining an interaction
 */
@protocol FBAMDServiceConnectionTransfer <NSObject>

/**
 Synchronously send bytes on the connection.

 @param data the data to send
 @param error an error out for any error that occurs.
 @return YES if the bytes were sent, NO otherwise.
 */
- (BOOL)send:(NSData *)data error:(NSError **)error;

/**
 Synchronously send bytes on the connection, prefixed with a length packet.

 @param data the data to send>
 @param error an error out for any error that occurs.
 @return YES if the bytes were sent, NO otherwise.
 */
- (BOOL)sendWithLengthHeader:(NSData *)data error:(NSError **)error;

/**
 Synchronously receive bytes from the connection.

 @param size the number of bytes to read.
 @param error an error out for any error that occurs.
 @return the data.
 */
- (NSData *)receive:(size_t)size error:(NSError **)error;

/**
 Synchronously recieve bytes into a buffer.

 @param destination the destination to write into.
 @param size the number of bytes to read.
 @param error an error out for any error that occurs.
 @return YES if all bytes read, NO otherwise.
 */
- (BOOL)receive:(void *)destination ofSize:(size_t)size error:(NSError **)error;

@end

/**
 Wraps the AMDServiceConnection.
 */
@interface FBAMDServiceConnection : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param connection the connection to use.
 @param device the device to use.
 @param calls the calls to use.
 @param logger the logger to use.
 @return a FBAMDServiceConnection instance.
 */
- (instancetype)initWithServiceConnection:(AMDServiceConnectionRef)connection device:(AMDeviceRef)device calls:(AMDCalls)calls logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Raw Data

/**
 Obtains a transfer object for raw socket transfer.
 */
- (id<FBAMDServiceConnectionTransfer>)rawSocket;

/**
 Obtains a transfer object for a service-API based transfer.
 */
- (id<FBAMDServiceConnectionTransfer>)serviceConnectionWrapped;

#pragma mark plist Messaging

// There's a common protocol that is commonly used with AMDServiceConnections (otherwise known as lockdown services).
// As this is used by a number of different services, there's library code for this protocol in MobileDevice.framework
// This format is built on top of sending and receiving from the AMDServiceConnection socket.
// It's implemented in the AMDServiceConnectionSendMessage/AMDServiceConnectionReceiveMessage calls, but can also be implemented manually.
// One reason for using these calls instead of sending raw bytes is that these library functions send encrypted traffic if there's an SSL context on the AMDServiceConnection.
// Over the course of iOS releases, the requirement to send data using SSL has become more strictly enforced.
//
// The send-side of the protocol is as follows:
// 1) Any packet has a device-endian 32-bit unsigned integer that encodes the length of a packet. This is used for both the sending and recieving side.
// 2) The data after this is a binary-plist of the payload itself. This means that any plist-serializable data can be transmitted.
// 3) There is no trailer for a packet, the header defines when the end of the packet is.
// 4) The header (#1) and the binary plist (#2) are then sent over the socket. If there's an SSL context then any data that is transmitted is encrypted. When encryption is enabled, all data on the channel is encrypted, including the header
//
// The receive side is just the same, but in reverse:
// 1) The header is read, it's of a fixed size so the socket receive call can be provided with a fixed value
// 2) The header gives the size of the plist-packet read length. Once the read side has read up to the size of the payload, it is ready to be deserialized.
// 3) As with the write side, if there's an SSL context the data will be decrypted through this context.

/**
 Synchronously recieve a plist-based packet used by lockdown.

 @param message the message to send.
 @param error an error out for any error that occurs.
 @return YES if the message was sent, NO otherwise.
 */
- (BOOL)sendMessage:(id)message error:(NSError **)error;

/**
 Synchronously recieve a plist-based packet used by lockdown.

 @param error an error out for any error that occurs.
 @return the read plist.
 */
- (id)receiveMessageWithError:(NSError **)error;

/**
 Send then receive a plist.

 @param message the message to send.
 @param error an error out for any error that occurs.
 @return the message received, if successful.
 */
- (id)sendAndReceiveMessage:(id)message error:(NSError **)error;

#pragma mark Streams

/**
 Reads the stream on the given queue, until exhausted.

 @param consumer the consumer to use.
 @param queue the queue to consume on.
 @return a Future that resolves once consumption has finished.
*/
- (FBFuture<NSNull *> *)consume:(id<FBDataConsumer>)consumer onQueue:(dispatch_queue_t)queue;

#pragma mark Lifecycle

/**
 Invalidates the Service connection.
 After this is called, this object is no longer valid.

 @param error an error out for any error that occurs.
 @return YES is succesful, NO otherwise.
 */
- (BOOL)invalidateWithError:(NSError **)error;

/**
 Build a service connection client, returning it in an FBFutureContext.

 @param logger the logger to use.
 @param queue the queue to execute on
 @return an FBFutureContext wrapping the client.
 */
- (FBFutureContext<FBServiceConnectionClient *> *)makeClientWithLogger:(id<FBControlCoreLogger>)logger  queue:(dispatch_queue_t)queue;

#pragma mark Properties

/**
 The Wrapped Connection.
 */
@property (nonatomic, assign, readonly, nullable) AMDServiceConnectionRef connection;

/**
 The Device to use.
 */
@property (nonatomic, assign, readonly) AMDeviceRef device;

/**
 The Calls to use.
 */
@property (nonatomic, assign, readonly) AMDCalls calls;

/**
 The Logger to use.
 */
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

/**
 The socket for the connection.
 */
@property (nonatomic, assign, readonly) int socket;

/**
 The Secure IO Context.
 */
@property (nonatomic, assign, readonly) AMSecureIOContext secureIOContext;

@end

NS_ASSUME_NONNULL_END
