/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBUploadHeader;
@class FBUploadedDestination;
@class FBiOSActionRouter;

@protocol FBiOSTarget;
@protocol FBiOSTargetFuture;
@protocol FBiOSActionReaderDelegate;

/**
 The Termination Handle Type for an Action Reader.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeActionReader;

/**
 Routes an Actions for Sockets and Files.
 */
@interface FBiOSActionReader : NSObject <FBiOSTargetContinuation>

#pragma mark Initializers

/**
 Initializes an Action Reader for a target, on a socket.
 The default routing of the target will be used.

 @param target the target to run against.
 @param delegate the delegate to notify.
 @param port the port to bind on.
 @return a Socket Reader.
 */
+ (instancetype)socketReaderForTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSActionReaderDelegate>)delegate port:(in_port_t)port;


/**
 Initializes an Action Reader for a router, on a socket.
 The Designated Initializer.

 @param router the router to use.
 @param delegate the delegate to notify.
 @param port the port to bind on.
 @return a Socket Reader.
 */
+ (instancetype)socketReaderForRouter:(FBiOSActionRouter *)router delegate:(id<FBiOSActionReaderDelegate>)delegate port:(in_port_t)port;

/**
 Initializes an Action Reader for a router, between file handles.
 The default routing of the target will be used.

 @param target the target to run against.
 @param delegate the delegate to notify.
 @param readHandle the handle to read.
 @param writeHandle the handle to write to.
 @return a Socket Reader.
 */
+ (instancetype)fileReaderForTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSActionReaderDelegate>)delegate readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle;

/**
 Initializes an Action Reader for a router, between file handles.

 @param router the router to use.
 @param delegate the delegate to notify.
 @param readHandle the handle to read.
 @param writeHandle the handle to write to.
 @return a Socket Reader.
 */
+ (instancetype)fileReaderForRouter:(FBiOSActionRouter *)router delegate:(id<FBiOSActionReaderDelegate>)delegate readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle;

#pragma mark Public Methods

/**
 Create and Listen to the socket.

 @return A future that starts when listening has started.
 */
- (FBFuture<NSNull *> *)startListening;

/**
 Stop listening to the socket

 @return A future that starts when listening has started.
 */
- (FBFuture<NSNull *> *)stopListening;

@end

/**
 The Delegate for the Action Reader.
 */
@protocol FBiOSActionReaderDelegate <FBEventReporter>

/**
 Called when the Reader has finished reading.

 @param reader the reader.
 */
- (void)readerDidFinishReading:(FBiOSActionReader *)reader;

/**
 Called when the Reader failed to interpret some input.

 @param reader the reader.
 @param input the line of input
 @param error the generated error.
 */
- (nullable NSString *)reader:(FBiOSActionReader *)reader failedToInterpretInput:(NSString *)input error:(NSError *)error;

/**
 Called when the Reader failed to interpret some input.

 @param reader the reader.
 @param header the header of the file being uploaded.
 @return the string to write back to the reader, if relevant.
 */
- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartReadingUpload:(FBUploadHeader *)header;

/**
 Called when the Reader failed to interpret some input.

 @param reader the reader.
 @param destination the destination of the upload.
 @return the string to write back to the reader, if relevant.
 */
- (nullable NSString *)reader:(FBiOSActionReader *)reader didFinishUpload:(FBUploadedDestination *)destination;

/**
 Called when the Reader is about to perform an action.

 @param reader the reader performing the action
 @param action the action to be performed
 @param target the target
 @return the string to write back to the reader, if relevant.
 */
- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartPerformingAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target;

/**
 Called when the Reader has successfully performed an action

 @param reader the reader performing the action
 @param action the action to be performed
 @param target the target
 @return the string to write back to the reader, if relevant.
*/
- (nullable NSString *)reader:(FBiOSActionReader *)reader didProcessAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target;

/**
 Called when the Reader has failed to perform an action

 @param reader the reader performing the action
 @param action the action to be performed
 @param target the target
 @param error the error.
 @return the string to write back to the reader, if relevant.
 */
- (nullable NSString *)reader:(FBiOSActionReader *)reader didFailToProcessAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target error:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
