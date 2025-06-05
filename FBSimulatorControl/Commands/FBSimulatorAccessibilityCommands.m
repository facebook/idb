/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorAccessibilityCommands.h"

#import <objc/runtime.h>

#import <CoreSimulator/SimDevice.h>
#import <AccessibilityPlatformTranslation/AXPTranslator.h>
#import <AccessibilityPlatformTranslation/AXPTranslationObject.h>
#import <AccessibilityPlatformTranslation/AXPTranslatorResponse.h>
#import <AccessibilityPlatformTranslation/AXPTranslatorRequest.h>
#import <AccessibilityPlatformTranslation/AXPMacPlatformElement.h>

#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"

//
// # About the implementation of Accessibility within CoreSimulator
//
// In Xcode 12, using the SimulatorBridge for accessibility is now gone.
// Instead, this functionality is bridged via CoreSimulator. However, there are more mechanisms in play than just calling a function.
// The Private Framework AccessibilityPlatformTranslation, is used by Simulator.app via SimulatorKit.
// In Simulator.app, it uses NSView semantics for obtaining information about a Simulator, in the case of FBSimulatorControl we aren't necessarily view-backed.
// As a result we are using a reverse-engineered implementation of how SimulatorKit functions, based on inputs to this API.
//
// For this to work the process is as follows:
// - The AXPTranslator is used to do all of the wiring for providing high-level objects that can be interrogated.
// - To do this AXPTranslator uses delegation for performing the underlying accessibility request.
// - The delegation can be tokenized (optionally)
// - The requests are implemented by bridging to CoreSimulator. This is essentially the glue between high-level Accessibility APIs and CoreSimulator's implementation of them.
// - CoreSimulator doesn't actually implement the Accessibility fetches itself. Instead it calls out to an XPC service that is running inside the Simulator.
// - CoreSimulator's API for doing this fetch is Asynchronous, but AXPTranslator's delegation & fetching is not. To smooth over the gaps we have to wait on the result.
// - The reason for non-async APIs here is that AXMacPlatformElement has lazy property access; over time each of the values that are referenced will be filled out with this delegation.
// - The lazy property access can be seen in the logging here, where the AXPTranslatorRequest has a nice description of the object.
// - Additional methods are required in the delegation, depending on whether there needs to be additional transformation, as is in the case with translating co-ordinate systems.
// - We smooth over the differences in the values returned in the legacy API by replicating the values returned by the SimulatorBridge, calling the appropriate methods on AXMacPlatformElement.
// - To get an idea of what methods are usable, take a look as NSAccessibilityElement which is a supertype of AXMacPlatformElement.
// - The tokenized method appears to be the more recent one. The token isn't significant for us so in this case we can just pass a meaningless token that will be received from all delegate callbacks.s
//
// All of the above could be implemented without the delegation system. However, this requires dumping large enums and going much lower in the protocol level.
// Instead having the higher level object, liberated from SimulatorKit (and therefore views) is the best compromise and the lightest touch.
//
// The only exception here is the usage of -[NSAccessibility accessibilityParent] which calls a delegate method with an unknown implementation.
// Since all values are enumerated recursively downwards, this is fine for the time being.
//
// We must also remember to set the `bridgeDelegateToken` on all created `AXPTranslationObject`s.
// This applies to those created by us when the `AXPTranslationObject` as well`AXPMacPlatformElement`'s that are created inside `AccessibilityPlatformTranslation`
// This is needed so that we know which Simulator the request belongs to, since the Translator is a singleton object, we need to be able to de-duplicate here.
//

inline static id ensureJSONSerializable(id obj)
{
  if (obj == nil) {
    return NSNull.null;
  }
  return [NSJSONSerialization isValidJSONObject:@[obj]] ? obj : [obj description];
}

@interface FBSimulatorAccessibilitySerializer : NSObject

@end

@implementation FBSimulatorAccessibilitySerializer

static NSString *const AXPrefix = @"AX";

+ (NSArray<NSDictionary<NSString *, id> *> *)recursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token nestedFormat:(BOOL)nestedFormat
{
  element.translation.bridgeDelegateToken = token;
  if (nestedFormat) {
    return @[[self.class nestedRecursiveDescriptionFromElement:element token:token]];
  }
  return [self.class flatRecursiveDescriptionFromElement:element token:token];
}

+ (NSDictionary<NSString *, id> *)formattedDescriptionOfElement:(AXPMacPlatformElement *)element token:(NSString *)token nestedFormat:(BOOL)nestedFormat
{
  element.translation.bridgeDelegateToken = token;
  if (nestedFormat) {
    return [self.class nestedRecursiveDescriptionFromElement:element token:token];
  }
  return [self.class accessibilityDictionaryForElement:element token:token];
}

// The values here are intended to mirror the values in the old SimulatorBridge implementation for compatibility downstream.
+ (NSDictionary<NSString *, id> *)accessibilityDictionaryForElement:(AXPMacPlatformElement *)element token:(NSString *)token
{
  // The token must always be set so that the right callback is called
  element.translation.bridgeDelegateToken = token;

  NSRect frame = element.accessibilityFrame;
  // The value returned in accessibilityRole is may be prefixed with "AX".
  // If that's the case, then let's strip it to make it like the SimulatorBridge implementation.
  NSString *role = element.accessibilityRole;
  if ([role hasPrefix:AXPrefix]) {
    role = [role substringFromIndex:2];
  }
  NSMutableArray<NSString *> *customActions = [[NSMutableArray alloc] init];
  for (NSString *name in [element.accessibilityCustomActions valueForKey:@"name"]) {
    [customActions addObject:ensureJSONSerializable(name)];
  }
  return @{
    // These values are the "legacy" values that mirror their equivalents in SimulatorBridge
    @"AXLabel": ensureJSONSerializable(element.accessibilityLabel),
    @"AXFrame": NSStringFromRect(frame),
    @"AXValue": ensureJSONSerializable(element.accessibilityValue),
    @"AXUniqueId": ensureJSONSerializable(element.accessibilityIdentifier),
    // There are additional synthetic values from the old output.
    @"type": ensureJSONSerializable(role),
    // These are new values in this output
    @"title": ensureJSONSerializable(element.accessibilityTitle),
    @"frame": @{
      @"x": @(frame.origin.x),
      @"y": @(frame.origin.y),
      @"width": @(frame.size.width),
      @"height": @(frame.size.height),
    },
    @"help": ensureJSONSerializable(element.accessibilityHelp),
    @"enabled": @(element.accessibilityEnabled),
    @"custom_actions": [customActions copy],
    @"role": ensureJSONSerializable(element.accessibilityRole),
    @"role_description": ensureJSONSerializable(element.accessibilityRoleDescription),
    @"subrole": ensureJSONSerializable(element.accessibilitySubrole),
    @"content_required": @(element.accessibilityRequired),
    @"pid": @(element.translation.pid),
  };
}

// This replicates the non-hierarchical system that was previously present in SimulatorBridge.
// In this case the values of frames must be relative to the root, rather than the parent frame.
+ (NSArray<NSDictionary<NSString *, id> *> *)flatRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token
{
  NSMutableArray<NSDictionary<NSString *, id> *> *values = NSMutableArray.array;
  [values addObject:[self accessibilityDictionaryForElement:element token:token]];
  for (AXPMacPlatformElement *childElement in element.accessibilityChildren) {
    childElement.translation.bridgeDelegateToken = token;
    NSArray<NSDictionary<NSString *, id> *> *childValues = [self flatRecursiveDescriptionFromElement:childElement token:token];
    [values addObjectsFromArray:childValues];
  }
  return values;
}

+ (NSDictionary<NSString *, id> *)nestedRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element token:(NSString *)token
{
  NSMutableDictionary<NSString *, id> *values = [[self accessibilityDictionaryForElement:element token:token] mutableCopy];
  NSMutableArray<NSDictionary<NSString *, id> *> *childrenValues = NSMutableArray.array;
  for (AXPMacPlatformElement *childElement in element.accessibilityChildren) {
    childElement.translation.bridgeDelegateToken = token;
    NSDictionary<NSString *, id> *childValues = [self nestedRecursiveDescriptionFromElement:childElement token:token];
    [childrenValues addObject:childValues];
  }
  values[@"children"] = childrenValues;
  return values;
}

@end

static NSString *const DummyBridgeToken = @"FBSimulatorAccessibilityCommandsDummyBridgeToken";

@interface FBSimulatorAccessibilityCommands_SimulatorBridge : NSObject <FBAccessibilityOperations, FBSimulatorAccessibilityOperations>

@property (nonatomic, strong, readonly) FBSimulatorBridge *bridge;

@end

@implementation FBSimulatorAccessibilityCommands_SimulatorBridge

- (instancetype)initWithBridge:(FBSimulatorBridge *)bridge
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bridge = bridge;

  return self;
}

#pragma mark FBSimulatorAccessibilityCommands Implementation

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElementsWithNestedFormat:(BOOL)nestedFormat
{
  if (nestedFormat) {
    return [[FBControlCoreError
      describe:@"Nested Format is not supported for SimulatorBridge based accessibility"]
      failFuture];
  }
  return [self.bridge accessibilityElements];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat
{
  if (nestedFormat) {
    return [[FBControlCoreError
      describe:@"Nested Format is not supported for SimulatorBridge based accessibility"]
      failFuture];
  }
  return [self.bridge accessibilityElementAtPoint:point];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityPerformTapOnElementAtPoint:(CGPoint)point expectedLabel:(NSString *)expectedLabel
{
  return [[FBControlCoreError
    describeFormat:@"%@ is not supported for SimulatorBridge based accessibility", NSStringFromSelector(_cmd)]
    failFuture];
}

@end

@interface FBSimulator_TranslationRequest : NSObject

@property (nonatomic, assign, readonly) BOOL nestedFormat;
@property (nonatomic, copy, readonly) NSString *token;

@end

@implementation FBSimulator_TranslationRequest

- (instancetype)initWithNestedFormat:(BOOL)nestedFormat
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _token = NSUUID.UUID.UUIDString;
  _nestedFormat = nestedFormat;

  return self;
}

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (nullable id)serialize:(AXPMacPlatformElement *)element error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (instancetype)cloneWithNewToken
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@interface FBSimulator_TranslationRequest_FrontmostApplication : FBSimulator_TranslationRequest

@end

@implementation FBSimulator_TranslationRequest_FrontmostApplication

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  return [translator frontmostApplicationWithDisplayId:0 bridgeDelegateToken:self.token];
}

- (nullable id)serialize:(AXPMacPlatformElement *)element error:(NSError **)error
{
  return [FBSimulatorAccessibilitySerializer recursiveDescriptionFromElement:element token:self.token nestedFormat:self.nestedFormat];
}

- (instancetype)cloneWithNewToken
{
  return [[FBSimulator_TranslationRequest_FrontmostApplication alloc] initWithNestedFormat:self.nestedFormat];
}

@end

@interface FBSimulator_TranslationAction : NSObject

@property (nonatomic, assign, readonly) BOOL performTap;
@property (nonatomic, assign, readonly) CGPoint point;
@property (nonatomic, copy, nullable, readonly) NSString *expectedLabel;

@end

@implementation FBSimulator_TranslationAction

- (instancetype)initWithPerformTap:(BOOL)performTap expectedLabel:(nullable NSString *)expectedLabel point:(CGPoint)point;
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _performTap = performTap;
  _point = point;
  _expectedLabel = expectedLabel;

  return self;
}

- (BOOL)performActionOnElement:(AXPMacPlatformElement *)element error:(NSError **)error
{
  NSString *expectedLabel = self.expectedLabel;
  if (expectedLabel) {
    NSString *actualLabel = element.accessibilityLabel;
    if (![expectedLabel isEqualToString:actualLabel]) {
      return [[FBSimulatorError
        describeFormat:@"The element at point %@ does not have the expected label %@. Actual label %@", NSStringFromPoint(self.point), expectedLabel, actualLabel]
        failBool:error];
    }
  }
  if (self.performTap) {
    NSArray<NSString *> *actionNames = element.accessibilityActionNames;
    if ([actionNames containsObject:@"AXPress"] == NO) {
      return [[FBSimulatorError
        describeFormat:@"The element at point %@ with label %@ does not support pressing. Supported actions %@", NSStringFromPoint(self.point), element.accessibilityIdentifier, [FBCollectionInformation oneLineDescriptionFromArray:actionNames]]
        failBool:error];
    }
    if ([element accessibilityPerformPress] == NO) {
      return [[FBSimulatorError
        describeFormat:@"Performing accessibilityPerformPress on element at point %@ with label %@ did not succeed", NSStringFromPoint(self.point), element.accessibilityIdentifier]
        failBool:error];
    }
  }
  return YES;
}

@end

@interface FBSimulator_TranslationRequest_Point : FBSimulator_TranslationRequest

@property (nonatomic, assign, readonly) CGPoint point;
@property (nonatomic, strong, nullable, readonly) FBSimulator_TranslationAction *action;

@end

@implementation FBSimulator_TranslationRequest_Point

- (instancetype)initWithNestedFormat:(BOOL)nestedFormat point:(CGPoint)point action:(FBSimulator_TranslationAction *)action
{
  self = [super initWithNestedFormat:nestedFormat];
  if (!self) {
    return nil;
  }

  _point = point;
  _action = action;

  return self;
}

- (AXPTranslationObject *)performWithTranslator:(AXPTranslator *)translator
{
  return [translator objectAtPoint:self.point displayId:0 bridgeDelegateToken:self.token];
}

- (NSDictionary<NSString *, id> *)serialize:(AXPMacPlatformElement *)element error:(NSError **)error
{
  NSDictionary<NSString *, id> *result = [FBSimulatorAccessibilitySerializer formattedDescriptionOfElement:element token:self.token nestedFormat:self.nestedFormat];
  FBSimulator_TranslationAction *action = self.action;
  if (action && [action performActionOnElement:element error:error] == NO) {
    return nil;
  }
  return result;
}

- (instancetype)cloneWithNewToken
{
  return [[FBSimulator_TranslationRequest_Point alloc] initWithNestedFormat:self.nestedFormat point:self.point action:self.action];
}

@end


@interface FBSimulator_TranslationDispatcher : NSObject <AXPTranslationTokenDelegateHelper>

@property (nonatomic, weak, readonly) AXPTranslator *translator;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t callbackQueue;
@property (nonatomic, strong, readonly) NSMapTable<NSString *, FBSimulator *> *tokenToSimulator;

@end

@implementation FBSimulator_TranslationDispatcher

#pragma mark Initializers

- (instancetype)initWithTranslator:(AXPTranslator *)translator logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _translator = translator;
  _logger = logger;
  _callbackQueue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.accessibility_translator.callback", DISPATCH_QUEUE_SERIAL);
  _tokenToSimulator = [NSMapTable
    mapTableWithKeyOptions:NSPointerFunctionsCopyIn
    valueOptions:NSPointerFunctionsWeakMemory];

  return self;
}

+ (instancetype)sharedInstance
{
  static dispatch_once_t onceToken;
  static FBSimulator_TranslationDispatcher *dispatcher;
  dispatch_once(&onceToken, ^{
    AXPTranslator *translator = [objc_getClass("AXPTranslator") sharedInstance];
    // bridgeTokenDelegate is preferred by AXPTranslator.
    dispatcher = [[FBSimulator_TranslationDispatcher alloc] initWithTranslator:translator logger:nil];
    translator.bridgeTokenDelegate = dispatcher;
  });
  return dispatcher;
}

#pragma mark Public

- (FBFutureContext<NSArray<id> *> *)translationObjectAndMacPlatformElementForSimulator:(FBSimulator *)simulator request:(FBSimulator_TranslationRequest *)request
{
  return [[FBFuture
    onQueue:simulator.workQueue resolveValue:^ NSArray<id> * (NSError **error){
      [self pushSimulator:simulator token:request.token];
      AXPTranslationObject *translation = [request performWithTranslator:self.translator];
      if (translation == nil) {
        return [[FBSimulatorError
          describeFormat:@"No translation object returned for simulator. This means you have likely specified a point onscreen that is invalid or invisible due to a fullscreen dialog"]
          fail:error];
      }
      translation.bridgeDelegateToken = request.token;
      AXPMacPlatformElement *element = [self.translator macPlatformElementFromTranslation:translation];
      element.translation.bridgeDelegateToken = request.token;
      return @[translation, element];
    }]
    onQueue:simulator.workQueue contextualTeardown:^ FBFuture<NSNull *> * (id _, FBFutureState __){
      [self popSimulator:request.token];
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (NSString *)pushSimulator:(FBSimulator *)simulator token:(NSString *)token
{
  NSParameterAssert([self.tokenToSimulator objectForKey:token] == nil);
  [self.tokenToSimulator setObject:simulator forKey:token];
  [self.logger logFormat:@"Simulator %@ backed by token %@", simulator, token];
  return token;
}

- (FBSimulator *)popSimulator:(NSString *)token
{
  FBSimulator *simulator = [self.tokenToSimulator objectForKey:token];
  NSParameterAssert(simulator);
  [self.tokenToSimulator removeObjectForKey:token];
  [self.logger logFormat:@"Removing token %@", token];
  return simulator;
}

#pragma mark AXPTranslationTokenDelegateHelper

// Since we're using an async callback-based function in CoreSimulator this needs to be converted to a synchronous variant for the AXTranslator callbacks.
// In order to do this we have a dispatch group acting as a mutex.
// This also means that the queue that this happens on should **never be the main queue**. An async global queue will suffice here.
- (AXPTranslationCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token
{
  FBSimulator *simulator = [self.tokenToSimulator objectForKey:token];
  if (!simulator) {
    return ^ AXPTranslatorResponse * (AXPTranslatorRequest *request) {
      [self.logger logFormat:@"Simlator with token %@ is gone for request %@. Returning empty response", token, request];
      return [objc_getClass("AXPTranslatorResponse") emptyResponse];
    };
  }
  return ^ AXPTranslatorResponse * (AXPTranslatorRequest *request){
    [simulator.logger logFormat:@"Sending Accessibility Request %@", request];
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block AXPTranslatorResponse *response = nil;
    [simulator.device sendAccessibilityRequestAsync:request completionQueue:self.callbackQueue completionHandler:^(AXPTranslatorResponse *innerResponse) {
      response = innerResponse;
      dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [simulator.logger logFormat:@"Got Accessibility Response %@", response];
    return response;
  };
}

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token
{
  return rect;
}

- (id)accessibilityTranslationRootParentWithToken:(NSString *)token
{
  [self.logger logFormat:@"Delegate method '%@', with unknown implementation called with token %@. Returning nil.", NSStringFromSelector(_cmd), token];
  return nil;
}

@end

@interface FBSimulatorAccessibilityCommands_CoreSimulator : NSObject <FBAccessibilityOperations, FBSimulatorAccessibilityOperations>

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorAccessibilityCommands_CoreSimulator

- (instancetype)initWithSimulator:(FBSimulator *)simulator queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark FBSimulatorAccessibilityCommands Implementation

- (FBFuture<id> *)accessibilityElementsWithNestedFormat:(BOOL)nestedFormat
{
  FBSimulator_TranslationRequest *translationRequest = [[FBSimulator_TranslationRequest_FrontmostApplication alloc] initWithNestedFormat:nestedFormat];
  return [FBSimulatorAccessibilityCommands_CoreSimulator accessibilityElementWithTranslationRequest:translationRequest simulator:self.simulator remediationPermitted:YES];
}

- (FBFuture<id> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat
{
  FBSimulator_TranslationRequest *translationRequest = [[FBSimulator_TranslationRequest_Point alloc] initWithNestedFormat:nestedFormat point:point action:nil];
  return [FBSimulatorAccessibilityCommands_CoreSimulator accessibilityElementWithTranslationRequest:translationRequest simulator:self.simulator remediationPermitted:NO];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityPerformTapOnElementAtPoint:(CGPoint)point expectedLabel:(NSString *)expectedLabel
{
  FBSimulator_TranslationAction *action = [[FBSimulator_TranslationAction alloc] initWithPerformTap:YES expectedLabel:expectedLabel point:point];
  FBSimulator_TranslationRequest *translationRequest = [[FBSimulator_TranslationRequest_Point alloc] initWithNestedFormat:YES point:point action:action];
  return (FBFuture<NSDictionary<NSString *, id> *> *) [FBSimulatorAccessibilityCommands_CoreSimulator accessibilityElementWithTranslationRequest:translationRequest simulator:self.simulator remediationPermitted:NO];
}

#pragma mark Private

+ (FBFuture<id> *)accessibilityElementWithTranslationRequest:(FBSimulator_TranslationRequest *)request simulator:(FBSimulator *)simulator remediationPermitted:(BOOL)remediationPermitted
{
  return [[[[FBSimulator_TranslationDispatcher.sharedInstance
    translationObjectAndMacPlatformElementForSimulator:simulator request:request]
    // This next steps appends remediation information (if required).
    // The remediation detection has a short circuit so that the common case (no remediation required) is fast.
    onQueue:simulator.asyncQueue pend:^ FBFuture<NSArray<id> *> * (NSArray<id> *tuple){
      AXPTranslationObject *translationObject = tuple[0];
      AXPMacPlatformElement *macPlatformElement = tuple[1];
      // Only see if remediation is needed if requested. This also ensures that the attempt *after* remediation will not infinitely recurse.
      if (remediationPermitted) {
        return [[FBSimulatorAccessibilityCommands_CoreSimulator
          remediationRequiredForSimulator:simulator
          translationObject:translationObject
          macPlatformElement:macPlatformElement]
          onQueue:simulator.asyncQueue map:^ NSArray<id> * (NSNumber *remediationRequired) {
            return @[translationObject, macPlatformElement, remediationRequired];
          }];
      }
      return [FBFuture futureWithResult:@[translationObject, macPlatformElement, @NO]];
    }]
    onQueue:simulator.workQueue pop:^ id (NSArray<id> *tuple){
      // If remediation is required, then return an empty value, we pop the context here to finish the translation process.
      BOOL remediationRequired = [tuple[2] boolValue];
      if (remediationRequired) {
        return FBFuture.empty;
      }
      // Otherwise serialize now, when the context has popped the token is then deregistered.
      AXPMacPlatformElement *element = tuple[1];
      NSError *error = nil;
      id serialized = [request serialize:element error:&error];
      if (serialized == nil) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:serialized];
    }]
    onQueue:simulator.workQueue fmap:^ FBFuture<id> * (id result) {
      // At this point we will either have an empty result, or the result.
      // In the empty (remediation) state, then we should recurse, but not allow further remediation.
      if ([result isEqual:NSNull.null]) {
        FBSimulator_TranslationRequest *nextRequest = [request cloneWithNewToken];
        return [[self
          remediateSpringBoardForSimulator:simulator]
          onQueue:simulator.workQueue fmap:^ FBFuture<id> * (id _) {
            return [self accessibilityElementWithTranslationRequest:nextRequest simulator:simulator remediationPermitted:NO];
          }];
      }
      return [FBFuture futureWithResult:result];
    }];
}

static NSString *const CoreSimulatorBridgeServiceName = @"com.apple.CoreSimulator.bridge";

+ (FBFuture<NSNumber *> *)remediationRequiredForSimulator:(FBSimulator *)simulator translationObject:(AXPTranslationObject *)translationObject macPlatformElement:(AXPMacPlatformElement *)macPlatformElement
{
  // First perform a quick check, if the accessibility frame is zero, then this is indicative of the problem
  if (CGRectEqualToRect(macPlatformElement.accessibilityFrame, CGRectZero) == NO) {
    return [FBFuture futureWithResult:@(NO)];
  }
  // Then confirm whether the pid of the translation object represents a real pid within the simulator.
  // If it does not, then it likely means that we got the pid of the crashed SpringBoard.
  // A crashed SpringBoard, means that there is a new one running (or else the Simulator is completely hosed).
  // In this case, the remediation is to restart CoreSimulatorBridge, since the CoreSimulatorBridge needs restarting upon a crash.
  // In all likelihood CoreSimulatorBridge contains a constant reference to the pid of SpringBoard and the most effective way of resolving this is to stop it.
  // The Simulator's launchctl will then make sure that the SimulatorBridge is restarted (just like it does for SpringBoard itself).
  pid_t processIdentifier = translationObject.pid;
  return [[[simulator
    serviceNameForProcessIdentifier:processIdentifier]
    mapReplace:@(NO)]
    onQueue:simulator.workQueue handleError:^(NSError *error) {
      [simulator.logger logFormat:@"pid %d does not exist, this likely means that SpringBoard has restarted, %@ should be restarted", processIdentifier, CoreSimulatorBridgeServiceName];
      return [FBFuture futureWithResult:@(YES)];
    }];
}

+ (FBFuture<NSNull *> *)remediateSpringBoardForSimulator:(FBSimulator *)simulator
{
  return [[[simulator
    stopServiceWithName:CoreSimulatorBridgeServiceName]
    mapReplace:NSNull.null]
    rephraseFailure:@"Could not restart %@ bridge when attempting to remediate SpringBoard Crash", CoreSimulatorBridgeServiceName];
}

@end

@interface FBSimulatorAccessibilityCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAccessibilityCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)targets
{
  return [[self alloc] initWithSimulator:targets];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBSimulatorAccessibilityCommands Protocol Implementation

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElementsWithNestedFormat:(BOOL)nestedFormat
{
  return [[self
    implementationWithNestedFormat:nestedFormat]
    onQueue:self.simulator.asyncQueue fmap:^(id<FBAccessibilityOperations> implementation) {
      return [implementation accessibilityElementsWithNestedFormat:nestedFormat];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat
{
  return [[self
    implementationWithNestedFormat:nestedFormat]
    onQueue:self.simulator.asyncQueue fmap:^(id<FBAccessibilityOperations> implementation) {
      return [implementation accessibilityElementAtPoint:point nestedFormat:nestedFormat];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityPerformTapOnElementAtPoint:(CGPoint)point expectedLabel:(NSString *)expectedLabel
{
  return [[self
    implementationWithNestedFormat:YES]
    onQueue:self.simulator.asyncQueue fmap:^(id<FBAccessibilityOperations, FBSimulatorAccessibilityOperations> implementation) {
      return [implementation accessibilityPerformTapOnElementAtPoint:point expectedLabel:expectedLabel];
    }];
}

#pragma mark Private

- (FBFuture<id<FBAccessibilityOperations, FBSimulatorAccessibilityOperations>> *)implementationWithNestedFormat:(BOOL)nestedFormat
{
  // Post Xcode 12, FBSimulatorBridge will not work with accessibility.
  // Additionally, CoreSimulator **should** be upgraded, but if it hasn't then this will fail.
  // The CoreSimulator API **is** backwards compatible, since it updates CoreSimulator.framework at the system level.
  // However, this API is only usable from CoreSimulator if Xcode 12 has been *installed at some point in the past on the host*.
  FBSimulator *simulator = self.simulator;
  if (simulator.state != FBiOSTargetStateBooted) {
    return [[FBControlCoreError
      describeFormat:@"Cannot run accessibility commands against %@ as it is not booted", simulator]
      failFuture];
  }
  SimDevice *device = simulator.device;
  if (nestedFormat || FBXcodeConfiguration.isXcode12OrGreater) {
    if (![device respondsToSelector:@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:)]) {
      return [[FBControlCoreError
        describeFormat:@"-[SimDevice %@] is not present on this host, you must install and/or use Xcode 12 to use the nested accessibility format.", NSStringFromSelector(@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:))]
        failFuture];
    }
    return [FBFuture futureWithResult:[[FBSimulatorAccessibilityCommands_CoreSimulator alloc] initWithSimulator:simulator queue:simulator.asyncQueue logger:simulator.logger]];
  }
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.asyncQueue map:^(FBSimulatorBridge *bridge) {
      return [[FBSimulatorAccessibilityCommands_SimulatorBridge alloc] initWithBridge:bridge];
    }];
}

@end
