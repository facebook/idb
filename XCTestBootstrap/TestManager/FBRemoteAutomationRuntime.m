/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBRemoteAutomationRuntime.h"

#import <objc/runtime.h>
#import <unistd.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXSocketTransport.h>
#import <DTXConnectionServices/DTXTransport.h>
#import <XCTestPrivate/DTXConnection-XCTestAdditions.h>
#import <XCTestPrivate/DTXProxyChannel-XCTestAdditions.h>
#import <XCTestPrivate/XCAccessibilityElement.h>
#import <XCTestPrivate/XCPointerEventPath.h>
#import <XCTestPrivate/XCSynthesizedEventRecord.h>

static NSString *const FBRemoteAutomationRuntimeErrorDomain = @"com.facebook.FBRemoteAutomationRuntime";

@implementation FBRemoteAutomationRuntime

+ (nullable id)failWithError:(NSError **)error format:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  if (error) {
    *error = [NSError errorWithDomain:FBRemoteAutomationRuntimeErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
  }
  return nil;
}

+ (nullable DTXConnection *)connectionForSocketHandle:(int)socketHandle
                                  transportDisconnect:(void (^)(void))transportDisconnect
                                 connectionDisconnect:(void (^)(void))connectionDisconnect
                                                error:(NSError **)error
{
  DTXTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socketHandle disconnectAction:transportDisconnect];
  if (!transport) {
    close(socketHandle);
    return [self failWithError:error format:@"DTXSocketTransport is unavailable; is DTXConnectionServices loaded?"];
  }
  DTXConnection *connection = [[objc_lookUpClass("DTXConnection") alloc] initWithTransport:transport];
  if (!connection) {
    return [self failWithError:error format:@"DTXConnection is unavailable; is DTXConnectionServices loaded?"];
  }
  [connection registerDisconnectHandler:connectionDisconnect];
  return connection;
}

+ (nullable DTXProxyChannel *)proxyChannelForConnection:(DTXConnection *)connection
                                         exportedObject:(id)exportedObject
                                                  queue:(dispatch_queue_t)queue
                                                  error:(NSError **)error
{
  // The daemon routes the channel by the interface protocol names (the DTX channel identifier
  // derives from them), so both interfaces use the daemon's real names (host-declared in
  // FBRemoteAutomationProtocols.h, not imported from Apple's umbrella). DTX also validates that
  // `exportedObject` conforms to the exported interface before opening the channel.
  DTXProxyChannel *proxyChannel = [connection xct_makeProxyChannelWithRemoteInterface:@protocol(XCTDRemoteAutomationServer) exportedInterface:@protocol(XCTDRemoteAutomationClient)];
  if (!proxyChannel) {
    return [self failWithError:error format:@"Failed to create a remote-automation proxy channel"];
  }
  // The channel needs the decodable-class allow-list installed before `resume`, or the daemon drops
  // the channel on the first invocation. `setAdditionalAllowedClassesForProtocolMethods:` is a
  // one-shot, so it must carry the handshake return types (XCTCapabilities…) and the read return
  // types (XCAccessibilityElement…) in a single set: `xct_setAllowedClassesForTestingProtocols`
  // whitelists only the base testing classes, so read returns would secure-decode to nil.
  [proxyChannel setExportedObject:exportedObject queue:queue];
  [proxyChannel setAdditionalAllowedClassesForProtocolMethods:[self allowedReturnClasses]];
  return proxyChannel;
}

+ (id<XCTDRemoteAutomationServer>)remoteProxyForChannel:(DTXProxyChannel *)proxyChannel
{
  return proxyChannel.remoteObjectProxy;
}

+ (NSSet *)allowedReturnClasses
{
  NSMutableSet *classes = [NSMutableSet set];
  // The private return types are runtime-loaded via XCTest.framework: the handshake capabilities
  // exchange (XCTCapabilities…) and the read path's element/snapshot types.
  for (NSString *name in @[@"XCAccessibilityElement", @"XCElementSnapshot", @"XCUIElementSnapshot", @"XCTCapabilities", @"XCTCapabilitiesBuilder", @"XCActivityRecord", @"XCTAttachment"]) {
    Class class = NSClassFromString(name);
    if (class) {
      [classes addObject:class];
    }
  }
  [classes addObjectsFromArray:@[
    NSObject.class,
    NSArray.class,
    NSMutableArray.class,
    NSDictionary.class,
    NSMutableDictionary.class,
    NSString.class,
    NSAttributedString.class,
    NSNumber.class,
    NSValue.class,
    NSData.class,
    NSDate.class,
    NSError.class,
    NSNull.class,
    NSSet.class,
    NSURL.class,
    NSUUID.class,
   ]];
  return classes;
}

+ (nullable id)pointerEventPathForTouchAtX:(double)x y:(double)y error:(NSError **)error
{
  Class pathClass = objc_lookUpClass("XCPointerEventPath");
  if (!pathClass) {
    return [self failWithError:error format:@"XCPointerEventPath is unavailable; is XCTest.framework loaded?"];
  }
  return [[pathClass alloc] initForTouchAtPoint:CGPointMake(x, y) offset:0];
}

+ (nullable id)synthesizedEventRecordWithName:(NSString *)name pointerPaths:(NSArray<id> *)pointerPaths error:(NSError **)error
{
  Class recordClass = objc_lookUpClass("XCSynthesizedEventRecord");
  if (!recordClass) {
    return [self failWithError:error format:@"XCSynthesizedEventRecord is unavailable; is XCTest.framework loaded?"];
  }
  XCSynthesizedEventRecord *record = [[recordClass alloc] initWithName:name displayID:0 interfaceOrientation:1];
  for (XCPointerEventPath *pointerPath in pointerPaths) {
    [record addPointerEventPath:pointerPath];
  }
  return record;
}

+ (nullable id)applicationElementForProcessIdentifier:(int)processIdentifier error:(NSError **)error
{
  Class elementClass = objc_lookUpClass("XCAccessibilityElement");
  if (!elementClass) {
    return [self failWithError:error format:@"XCAccessibilityElement is unavailable; is XCTest.framework loaded?"];
  }
  return [elementClass elementWithProcessIdentifier:processIdentifier];
}

@end
