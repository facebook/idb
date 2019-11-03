/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

NS_ASSUME_NONNULL_BEGIN

@class ControlCoreLoggerBridge;
@protocol FBControlCoreLogger;

/**
 Bridging Preprocessor Macros to values, so that they can be read in Swift.
 */
@interface Constants : NSObject

@property (nonatomic, assign, readonly, class) int32_t asl_level_info;
@property (nonatomic, assign, readonly, class) int32_t asl_level_debug;
@property (nonatomic, assign, readonly, class) int32_t asl_level_err;

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

/**
 The components of the request.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *pathComponents;

/**
 The query dictionary of the request.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *query;

@end

/**
 A representation of a HTTP Response.
 */
@interface HttpResponse : NSObject

/**
 Creates a Response with the given status code.

 @param statusCode the status code.
 @param body the body to use.
 @param contentType the Content Type to use.
 @return a new Http Response Object.
 */
+ (instancetype)responseWithStatusCode:(NSInteger)statusCode body:(NSData *)body contentType:(NSString *)contentType;

/**
 Creates a Response with the given status code.

 @param statusCode the status code.
 @param body the body to use.
 @return a new Http Response Object.
 */
+ (instancetype)responseWithStatusCode:(NSInteger)statusCode body:(NSData *)body;

/**
 Creates a 500 Response.

 @param body the body to use.
 @return a new Http Response Object.
 */
+ (instancetype)internalServerError:(NSData *)body;

/**
 Creates a 200 Response.

 @param body the body to use.
 @return a new Http Response Object.
 */
+ (instancetype)ok:(NSData *)body;

/**
 The HTTP Status Code.
 */
@property (nonatomic, assign, readonly) NSInteger statusCode;

/**
 The Binary Data for the Body.
 */
@property (nonatomic, strong, readonly) NSData *body;

/**
 The content-type of the Response.
 */
@property (nonatomic, copy, readonly) NSString *contentType;

@end

@protocol HttpResponseHandler;

/**
 A representation of a HTTP Routing.
 */
@interface HttpRoute : NSObject

/**
 Creates a new route.

 @param method the HTTP Method to use.
 @param path the Relative Path to use.
 @param handler a handler for the request.
 @return a new HTTP Route.
 */
+ (instancetype)routeWithMethod:(NSString *)method path:(NSString *)path handler:(id<HttpResponseHandler>)handler;

/**
 The HTTP Method.
 */
@property (nonatomic, copy, readonly) NSString *method;

/**
 The Relative Path to use.
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 The Handler to use.
 */
@property (nonatomic, copy, readonly) id<HttpResponseHandler> handler;

@end

/**
 A Bridge between the Objective-C HTTP WebServer Implementation that can be used directly in FBSimulatorControlKit.
 */
@interface HttpServer : NSObject

/**
 Creates a Webserver.

 @param port the port to bind on.
 @param routes the routes to mount in the WebServer.
 @param logger an optional logger to use for logging requests.
 @return a new HttpServer instance.
 */
+ (instancetype)serverWithPort:(in_port_t)port routes:(NSArray<HttpRoute *> *)routes logger:(nullable id<FBControlCoreLogger>)logger;

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

/**
 A Handler for HTTP Requests.
 */
@protocol HttpResponseHandler <NSObject>

/**
 Handle the HTTP Request, returning a response.

 @param request the request to handle
 @return a HTTP Response
 */
- (HttpResponse *)handleRequest:(HttpRequest *)request;

@end

NS_ASSUME_NONNULL_END
