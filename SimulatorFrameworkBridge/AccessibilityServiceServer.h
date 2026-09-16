/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

int FBAXBridgeServe(NSString *socketPath, NSArray<NSString *> *arguments);

/** A framed response and whether the server should stop after writing it. */
@interface FBAXBridgeSocketResponse : NSObject
@property (nonatomic, readonly, copy) NSData *data;
@property (nonatomic, readonly) BOOL shutdown;
- (instancetype)initWithData:(NSData *)data shutdown:(BOOL)shutdown;
@end

/** Synchronous transport; both callbacks run on the thread that calls `serve`. */
@interface FBAXBridgeServer : NSObject
+ (int32_t)serveWithSocketPath:(NSString *)socketPath
            idleTimeoutSeconds:(int32_t)idleTimeoutSeconds
              exitOnDisconnect:(BOOL)exitOnDisconnect
                prepareRuntime:(void (^)(void))prepareRuntime
                 handleRequest:(FBAXBridgeSocketResponse *(^)(NSData *))handleRequest
  NS_SWIFT_NAME(serve(socketPath:idleTimeoutSeconds:exitOnDisconnect:prepareRuntime:handleRequest:));
@end

NS_ASSUME_NONNULL_END
