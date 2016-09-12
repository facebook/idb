/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

NS_ASSUME_NONNULL_BEGIN

@class ControlCoreLoggerBridge;

/**
 Bridging Preprocessor Macros to values, so that they can be read in Swift.
 */
@interface Constants : NSObject

+ (int32_t)sol_socket;
+ (int32_t)so_reuseaddr;

+ (int32_t)asl_level_info;
+ (int32_t)asl_level_debug;
+ (int32_t)asl_level_err;

@end

/**
 Coercion to JSON Serializable Representations
 */
@interface NSString (FBJSONSerializable) <FBJSONSerializable>
@end

@interface NSArray (FBJSONSerializable) <FBJSONSerializable>
@end

/**
 A Bridge between JSONEventReporter and FBSimulatorLogger.
 Since the FBSimulatorLoggerProtocol omits the varags logFormat: method,
 this Objective-C implementation can do the appropriate bridging.
 */
@interface LogReporter : NSObject <FBControlCoreLogger>

/**
 Constructs a new JSONLogger instance with the provided reporter.

 @param bridge the bridge to report messages to.
 @param debug YES if debug messages should be reported, NO otherwise.
 @return a new JSONLogger instance.
 */
- (instancetype)initWithBridge:(ControlCoreLoggerBridge *)bridge debug:(BOOL)debug;

@end

/**
 A representation of a HTTP Request.
 */
@interface HttpRequest : NSObject

/**
 The Body of the Request.
 */
@property (nonatomic, strong, readonly) NSData *body;

@end

/**
 A representation of a HTTP Response.
 */
@interface HttpResponse : NSObject

/**
 Creates a Response with the given status code.
 */
+ (instancetype)responseWithStatusCode:(NSInteger)statusCode body:(NSData *)body;

/**
 Creates a 500 Response.
 */
+ (instancetype)internalServerError:(NSData *)body;

/**
 Creates a 200 Response.
 */
+ (instancetype)ok:(NSData *)body;

@property (nonatomic, assign, readonly) NSInteger statusCode;
@property (nonatomic, strong, readonly) NSData *body;

@end

@interface HttpRoute : NSObject

+ (instancetype)routeWithMethod:(NSString *)method path:(NSString *)path handler:(HttpResponse *(^)(HttpRequest *))handler;

@property (nonatomic, copy, readonly) NSString *method;
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) HttpResponse *(^handler)(HttpRequest *request);

@end

/**
 A Bridge between the Objective-C HTTP WebServer Implementation that can be used directly in FBSimulatorControlKit.
 */
@interface HttpServer : NSObject

/**
 Creates a Webserver.

 @param port the port to bind on.
 */
+ (instancetype)serverWithPort:(in_port_t)port routes:(NSArray<HttpRoute *> *)routes;

/**
 Starts the Webserver.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startWithError:(NSError **)error;

/**
 Stops the Webserver.
 */
- (void)stop;

@end

NS_ASSUME_NONNULL_END
