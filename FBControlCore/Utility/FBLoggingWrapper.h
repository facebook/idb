/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBEventReporter;

/**
 Logs method invocations of the wrapped class to an event reporter.
 The events that will be logged on the wrapped object will be logged for any method invocation that returns a Future.
 The starting of the invocation will be logged as well as the completion, including any arguments.
 */
@interface FBLoggingWrapper : NSObject

/**
 Wraps all methods with logging to an event logger
 It logs: started and success / failure calls
 Each log contains the methodName and a truncated description of it's arguments

 @param wrappedObject the object to wrap, all methods must return an FBFuture.
 @param simplifiedNaming YES if the name of the first element in the selector should be used, NO if you want the full selector.
 @param eventReporter the event reporter to log to.
 @param logger FBControlCoreLogger to use.
 @return wrapper instance, that proxies the underlying wrapped object.
 */
+ (id)wrap:(id)wrappedObject simplifiedNaming:(BOOL)simplifiedNaming eventReporter:(nullable id<FBEventReporter>)eventReporter logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
