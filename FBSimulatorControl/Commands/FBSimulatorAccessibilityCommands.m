/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
// - The tokenized method appears to be the more recent one. The token isn't significant for us so in this case we can just pass a meaningless token that will be recieved from all delegate callbacks.s
//
// All of the above could be implemented without the delegation system. However, this requires dumping large enums and going much lower in the protocol level.
// Instead having the higher level object, liberated from SimulatorKit (and therefore views) is the best compromise and the lightest touch.
//
// The only exception here is the usage of -[NSAccessibility accessibilityParent] which calls a delegate method with an unknown implementation.
// Since all values are enumerated recursively downwards, this is fine for the time being.
//

static NSString *const DummyBridgeToken = @"FBSimulatorAccessibilityCommandsDummyBridgeToken";

@interface FBSimulatorAccessibilityCommands_SimulatorBridge : NSObject <FBAccessibilityOperations>

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

@end

@interface FBSimulatorAccessibilityCommands_CoreSimulator : NSObject <FBAccessibilityOperations, AXPTranslationDelegateHelper, AXPTranslationTokenDelegateHelper>

@property (nonatomic, strong, readonly) SimDevice *device;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBSimulatorAccessibilityCommands_CoreSimulator

- (instancetype)initWithDevice:(SimDevice *)device queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark FBSimulatorAccessibilityCommands Implementation

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElementsWithNestedFormat:(BOOL)nestedFormat
{
  AXPTranslator *translator = self.translator;
  AXPTranslationObject *translationObject = [translator frontmostApplicationWithDisplayId:0 bridgeDelegateToken:DummyBridgeToken];
  AXPMacPlatformElement *element = [translator macPlatformElementFromTranslation:translationObject];
  if (nestedFormat) {
    return [FBFuture futureWithResult:@[[self.class nestedRecursiveDescriptionFromElement:element]]];
  }
  return [FBFuture futureWithResult:[self.class flatRecursiveDescriptionFromElement:element]];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat
{
  AXPTranslator *translator = self.translator;
  AXPTranslationObject *translationObject = [translator objectAtPoint:point displayId:0 bridgeDelegateToken:DummyBridgeToken];
  AXPMacPlatformElement *element = [translator macPlatformElementFromTranslation:translationObject];
  if (nestedFormat) {
    return [FBFuture futureWithResult:[self.class nestedRecursiveDescriptionFromElement:element]];
  }
  return [FBFuture futureWithResult:[self.class accessibilityDictionaryForElement:element]];
}

#pragma mark Private

// This is basically the root class of how translation works.
- (AXPTranslator *)translator
{
  AXPTranslator *translator = [objc_getClass("AXPTranslator") sharedInstance];
  // bridgeTokenDelegate is preferred by AXPTranslator.
  translator.bridgeDelegate = self;
  translator.bridgeTokenDelegate = self;
  return translator;
}

// Since we're using an async callback-based function in CoreSimulator this needs to be converted to a synchronous variant for the AXTranslator callbacks.
// In order to do this we have a dispatch group acting as a mutex.
// This also means that the queue that this happens on should **never be the main queue**. An async global queue will suffice here.
+ (AXPTranslationCallback)translationCallbackForSimDevice:(SimDevice *)device queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return ^ AXPTranslatorResponse * (AXPTranslatorRequest *request){
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __block AXPTranslatorResponse *response = nil;
    [logger logFormat:@"Sending Accessibility Request %@", request];
    [device sendAccessibilityRequestAsync:request completionQueue:queue completionHandler:^(AXPTranslatorResponse *innerResponse) {
      response = innerResponse;
      dispatch_group_leave(group);
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [logger logFormat:@"Got Accessibility Response %@", response];
    return response;
  };
}

static NSString *const AXPrefix = @"AX";

// The values here are intended to mirror the values in the old SimulatorBridge implementation for compatibility downstream.
+ (NSDictionary<NSString *, id> *)accessibilityDictionaryForElement:(AXPMacPlatformElement *)element
{
  NSRect frame = element.accessibilityFrame;
  // The value returned in accessibilityRole is may be prefixed with "AX".
  // If that's the case, then let's strip it to make it like the SimulatorBridge implementation.
  NSString *role = element.accessibilityRole;
  if ([role hasPrefix:AXPrefix]) {
    role = [role substringFromIndex:2];
  }
  return @{
    // These values are the "legacy" values that mirror their equivalents in SimulatorBridge
    @"AXLabel": element.accessibilityLabel ?: NSNull.null,
    @"AXFrame": NSStringFromRect(frame),
    @"AXValue": element.accessibilityValue ?: NSNull.null,
    @"AXUniqueId": element.accessibilityIdentifier ?: NSNull.null,
    // There are additional synthetic values from the old output.
    @"type": role ?: NSNull.null,
    // These are new values in this output
    @"title": element.accessibilityTitle ?: NSNull.null,
    @"frame": @{
      @"x": @(frame.origin.x),
      @"y": @(frame.origin.y),
      @"width": @(frame.size.width),
      @"height": @(frame.size.height),
    },
    @"help": element.accessibilityHelp ?: NSNull.null,
    @"enabled": @(element.accessibilityEnabled),
    @"custom_actions": [element.accessibilityCustomActions valueForKey:@"name"] ?: @[],
    @"role": element.accessibilityRole ?: NSNull.null,
    @"role_description": element.accessibilityRoleDescription ?: NSNull.null,
    @"subrole": element.accessibilitySubrole ?: NSNull.null,
    @"content_required": @(element.accessibilityRequired),
  };
}

// This replicates the non-heirarchical system that was previously present in SimulatorBridge.
// In this case the values of frames must be relative to the root, rather than the parent frame.
+ (NSArray<NSDictionary<NSString *, id> *> *)flatRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element
{
  NSMutableArray<NSDictionary<NSString *, id> *> *values = NSMutableArray.array;
  [values addObject:[self accessibilityDictionaryForElement:element]];
  for (AXPMacPlatformElement *childElement in element.accessibilityChildren) {
    NSArray<NSDictionary<NSString *, id> *> *childValues = [self flatRecursiveDescriptionFromElement:childElement];
    [values addObjectsFromArray:childValues];
  }
  return values;
}

+ (NSDictionary<NSString *, id> *)nestedRecursiveDescriptionFromElement:(AXPMacPlatformElement *)element
{
  NSMutableDictionary<NSString *, id> *values = [[self accessibilityDictionaryForElement:element] mutableCopy];
  NSMutableArray<NSDictionary<NSString *, id> *> *childrenValues = NSMutableArray.array;
  for (AXPMacPlatformElement *childElement in element.accessibilityChildren) {
    NSDictionary<NSString *, id> *childValues = [self nestedRecursiveDescriptionFromElement:childElement];
    [childrenValues addObject:childValues];
  }
  values[@"children"] = childrenValues;
  return values;
}

#pragma mark AXPTranslationTokenDelegateHelper

- (AXPTranslationCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token
{
  return [self.class translationCallbackForSimDevice:self.device queue:self.queue logger:self.logger];
}

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token
{
  return rect;
}

- (id)accessibilityTranslationRootParentWithToken:(NSString *)token
{
  NSAssert(NO, @"Delegate method '%@', with unknown implementation called", NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark AXPTranslationDelegateHelper

- (AXPTranslationCallback)accessibilityTranslationDelegateBridgeCallback
{
  return [self.class translationCallbackForSimDevice:self.device queue:self.queue logger:self.logger];
}

- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withContext:(id)context postProcess:(id)postProcess
{
  return rect;
}

- (id)accessibilityTranslationRootParent
{
  NSAssert(NO, @"Delegate method '%@', with unknown implementation called", NSStringFromSelector(_cmd));
  return nil;
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
    onQueue:self.simulator.workQueue fmap:^(id<FBAccessibilityOperations> implementation) {
      return [implementation accessibilityElementsWithNestedFormat:nestedFormat];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat
{
  return [[self
    implementationWithNestedFormat:nestedFormat]
    onQueue:self.simulator.workQueue fmap:^(id<FBAccessibilityOperations> implementation) {
      return [implementation accessibilityElementAtPoint:point nestedFormat:nestedFormat];
    }];
}

#pragma mark Private

- (FBFuture<id<FBAccessibilityOperations>> *)implementationWithNestedFormat:(BOOL)nestedFormat
{
  // Post Xcode 12, FBSimulatorBridge will not work with accessibility.
  // Additionally, CoreSimulator **should** be upgraded, but if it hasn't then this will fail.
  // The CoreSimulator API **is** backwards compatible, since it updates CoreSimulator.framework at the system level.
  // However, this API is only usable from CoreSimulator if Xcode 12 has been *installed at some point in the past on the host*.
  FBSimulator *simulator = self.simulator;
  SimDevice *device = simulator.device;
  if (nestedFormat || FBXcodeConfiguration.isXcode12OrGreater) {
    if (![device respondsToSelector:@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:)]) {
      return [[FBControlCoreError
        describeFormat:@"-[SimDevice %@] is not present on this host, you must install and/or use Xcode 12 to use the nested accessibility format.", NSStringFromSelector(@selector(sendAccessibilityRequestAsync:completionQueue:completionHandler:))]
        failFuture];
    }
    return [FBFuture futureWithResult:[[FBSimulatorAccessibilityCommands_CoreSimulator alloc] initWithDevice:simulator.device queue:simulator.asyncQueue logger:simulator.logger]];
  }
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue map:^(FBSimulatorBridge *bridge) {
      return [[FBSimulatorAccessibilityCommands_SimulatorBridge alloc] initWithBridge:bridge];
    }];
}

@end
