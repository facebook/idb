/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "Bridging.h"

#import <asl.h>
#import <FBSimulatorControlKit/FBSimulatorControlKit-Swift.h>
#import <GCDWebServers/GCDWebServers.h>

@implementation Constants

+ (int32_t)asl_level_info
{
  return ASL_LEVEL_INFO;
}

+ (int32_t)asl_level_debug
{
  return ASL_LEVEL_DEBUG;
}

+ (int32_t)asl_level_err
{
  return ASL_LEVEL_ERR;
}

@end

@implementation NSString (FBJSONSerializable)

- (id)jsonSerializableRepresentation
{
  return self;
}

@end

@implementation NSArray (FBJSONSerializable)

- (id)jsonSerializableRepresentation
{
  return self;
}

@end

@interface LogReporter ()

@property (nonatomic, strong, readonly, nonnull) ControlCoreLoggerBridge *bridge;
@property (nonatomic, assign, readonly) int32_t currentLevel;
@property (nonatomic, assign, readonly) int32_t maxLevel;
@property (nonatomic, assign, readonly) BOOL dispatchToMain;

@end

@implementation LogReporter

#pragma mark Initializers

- (instancetype)initWithBridge:(ControlCoreLoggerBridge *)bridge debug:(BOOL)debug
{
  return [self initWithBridge:bridge currentLevel:ASL_LEVEL_INFO maxLevel:(debug ? ASL_LEVEL_DEBUG : ASL_LEVEL_INFO) dispatchToMain:NO];
}

- (instancetype)initWithBridge:(ControlCoreLoggerBridge *)bridge currentLevel:(int32_t)currentLevel maxLevel:(int32_t)maxLevel dispatchToMain:(BOOL)dispatchToMain;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bridge = bridge;
  _currentLevel = currentLevel;
  _maxLevel = maxLevel;
  _dispatchToMain = dispatchToMain;

  return self;
}

#pragma mark FBSimulatorLogger Interface

- (instancetype)log:(NSString *)string
{
  if (self.currentLevel > self.maxLevel) {
    return self;
  }

  if (self.dispatchToMain) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.bridge log:self.currentLevel string:string];
    });
  } else {
    [self.bridge log:self.currentLevel string:string];
  }

  return self;
}

- (instancetype)logFormat:(NSString *)format, ...
{
  if (self.currentLevel > self.maxLevel) {
    return self;
  }

  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_INFO maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)debug
{
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_DEBUG maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)error
{
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel dispatchToMain:self.dispatchToMain];
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  BOOL dispatchToMain = queue != dispatch_get_main_queue();
  return [[LogReporter alloc] initWithBridge:self.bridge currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel dispatchToMain:dispatchToMain];
}

- (id<FBControlCoreLogger>)withName:(NSString *)name
{
  // Ignore prefixing as 'subject' will be included instead.
  return self;
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled
{
  // Timestamps are provided in the json
  return self;
}

- (NSString *)name
{
  return nil;
}

- (FBControlCoreLogLevel)level
{
  return FBControlCoreLogLevelInfo;
}

@end

@implementation HttpRequest

- (instancetype)initWithBody:(NSData *)body pathComponents:(NSArray<NSString *> *)pathComponents query:(NSDictionary<NSString *, NSString *> *)query
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _body = body;
  _pathComponents = pathComponents;
  _query = query;

  return self;
}

@end

@implementation HttpResponse

+ (instancetype)responseWithStatusCode:(NSInteger)statusCode body:(NSData *)body contentType:(NSString *)contentType
{
  return [[self alloc] initWithStatusCode:statusCode body:body contentType:contentType];
}

+ (instancetype)responseWithStatusCode:(NSInteger)statusCode body:(NSData *)body
{
  return [self responseWithStatusCode:statusCode body:body contentType:@"application/json"];
}

+ (instancetype)internalServerError:(NSData *)body
{
  return [self responseWithStatusCode:500 body:body];
}

+ (instancetype)ok:(NSData *)body
{
  return [self responseWithStatusCode:200 body:body];
}

- (instancetype)initWithStatusCode:(NSInteger)statusCode body:(NSData *)body contentType:(NSString *)contentType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _statusCode = statusCode;
  _body = body;
  _contentType = contentType;

  return self;
}

@end

@interface HttpServer()

@property (nonatomic, assign, readonly) in_port_t port;
@property (nonatomic, strong, readonly) GCDWebServer *server;

@end

@implementation HttpServer

+ (instancetype)serverWithPort:(in_port_t)port routes:(NSArray<HttpRoute *> *)routes logger:(nullable id<FBControlCoreLogger>)logger
{
  GCDWebServer *server = [HttpServer webServerWithRoutes:routes logger:logger];
  return [[self alloc] initWithPort:port server:server];
}

- (instancetype)initWithPort:(in_port_t)port server:(GCDWebServer *)server
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _port = port;
  _server = server;

  return self;
}

- (BOOL)startWithError:(NSError **)error
{
  NSDictionary *options = @{
    GCDWebServerOption_Port: @(self.port),
    GCDWebServerOption_ServerName : [[NSBundle bundleForClass:self.class] bundleIdentifier],
  };
  return [self.server startWithOptions:options error:error];
}

- (void)stop
{
  [self.server stop];
}

+ (GCDWebServer *)webServerWithRoutes:(NSArray<HttpRoute *> *)routes logger:(nullable id<FBControlCoreLogger>)logger
{
  [GCDWebServer setLogLevel:5];
  GCDWebServer *webServer = [[GCDWebServer alloc] init];
  for (HttpRoute *route in routes) {
    [webServer addHandlerForMethod:route.method pathRegex:route.path requestClass:GCDWebServerDataRequest.class processBlock:^ GCDWebServerResponse *(GCDWebServerDataRequest *gcdRequest) {
      NSArray<NSString *> *components = [gcdRequest.path componentsSeparatedByString:@"/"];
      NSDictionary<NSString *, NSString *> *query = [HttpServer queryForRequest:gcdRequest];
      if (logger) {
        [logger logFormat:@"%@: %@", route.method, gcdRequest.path];
      }

      HttpRequest *request = [[HttpRequest alloc] initWithBody:gcdRequest.data pathComponents:components query:query];
      HttpResponse *response = [route.handler handleRequest:request];

      GCDWebServerDataResponse *gcdResponse = [GCDWebServerDataResponse responseWithData:response.body contentType:response.contentType];
      gcdResponse.statusCode = response.statusCode;
      return gcdResponse;
    }];
  }
  return webServer;
}

+ (NSDictionary<NSString *, NSString *> *)queryForRequest:(GCDWebServerRequest *)request
{
  NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
  for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO].queryItems) {
    query[item.name] = item.value;
  }
  return [query copy];
}

@end

@implementation HttpRoute

+ (instancetype)routeWithMethod:(NSString *)method path:(NSString *)path handler:(id<HttpResponseHandler>)handler
{
  return [[self alloc] initWithMethod:method path:path handler:handler];
}

- (instancetype)initWithMethod:(NSString *)method path:(NSString *)path handler:(id<HttpResponseHandler>)handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _method = method;
  _path = path;
  _handler = handler;

  return self;
}

@end
