/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "../AccessibilityRuntime.h"
#import "AccessibilitySnapshotClient.h"

NS_ASSUME_NONNULL_BEGIN

/** Owns an opaque runtime element. Only the Objective-C clients can unwrap it. */
@interface FBAXElement : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/** An absent value is an ordinary result; a nil result from a client method denotes an exception. */
@interface FBAXOptionalValue <__covariant ObjectType> : NSObject
@property (nullable, nonatomic, readonly) ObjectType value;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface FBAXElementHit : NSObject
@property (nonatomic, readonly) FBAXHitTestStatus status;
@property (nullable, nonatomic, readonly) FBAXElement *element;
@property (nonatomic, readonly) pid_t owningProcessIdentifier;
@property (nullable, nonatomic, readonly, copy) NSString *failureReason;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/** Children are wrapped only when the traversal asks for them. */
@interface FBAXElementRead : NSObject
@property (nonatomic, readonly) FBAXReadStatus status;
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, id> *attributes;
@property (nullable, nonatomic, readonly) NSError *error;
- (nullable NSArray<FBAXElement *> *)childrenWithError:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/** Semantic translator attributes, independent of its private numeric vocabulary. */
@interface FBAXTranslatorRead : NSObject
@property (nonatomic, readonly, getter = isAvailable) BOOL available;
@property (nullable, nonatomic, readonly) id label;
@property (nullable, nonatomic, readonly) id frame;
@property (nullable, nonatomic, readonly) id identifier;
@property (nullable, nonatomic, readonly) id value;
@property (nullable, nonatomic, readonly) id visible;
@property (nullable, nonatomic, readonly) id enabled;
@property (nullable, nonatomic, readonly) id role;
@property (nullable, nonatomic, readonly) id subrole;
@property (nullable, nonatomic, readonly) id visiblePoint;
@property (nullable, nonatomic, readonly) id traits;
@property (nullable, nonatomic, readonly) id memoryAddress;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/** Each interaction contains private exceptions before returning to Swift orchestration. */
@interface FBAXClient : NSObject
@property (nonatomic, readonly) FBAXSnapshotClient *snapshots;
- (instancetype)initWithRuntime:(id<FBAXRuntime>)runtime NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable FBAXOptionalValue<FBAXElement *> *)applicationElementForProcessIdentifier:(pid_t)pid error:(NSError **)error;
- (nullable FBAXElementRead *)readAttributes:(NSArray<NSString *> *)attributes ofElement:(FBAXElement *)element error:(NSError **)error;
- (nullable FBAXElementHit *)hitTestAtPoint:(CGPoint)point processIdentifier:(pid_t)pid error:(NSError **)error;
- (nullable FBAXWriteOutcome *)performAction:(FBAXAction)action onElement:(FBAXElement *)element error:(NSError **)error;
- (nullable FBAXWriteOutcome *)setValue:(id)value onElement:(FBAXElement *)element error:(NSError **)error;
- (nullable FBAXFrontmostOutcome *)windowServerFrontmostWithError:(NSError **)error;
- (nullable FBAXFrontmostOutcome *)runningBoardFrontmostWithError:(NSError **)error;
- (nullable NSNumber *)automationModeEnabledWithError:(NSError **)error;
- (nullable NSNumber *)setAutomationModeEnabled:(BOOL)enabled error:(NSError **)error;
- (nullable FBAXDeviceSettingOutcome *)enabledStateForDeviceSetting:(FBAXDeviceSetting)setting error:(NSError **)error;
- (nullable FBAXDeviceSettingOutcome *)setEnabled:(BOOL)enabled forDeviceSetting:(FBAXDeviceSetting)setting error:(NSError **)error;
- (nullable FBAXTranslatorRead *)translatorAttributesOfElement:(FBAXElement *)element error:(NSError **)error;
- (nullable NSArray<FBAXElement *> *)translatorChildrenOfElement:(FBAXElement *)element error:(NSError **)error;

/** Opaque inputs prevent Swift from enumerating a dictionary before entering the exception guard. */
- (nullable NSNumber *)isValidRectangleDictionary:(id)value error:(NSError **)error NS_SWIFT_NAME(isValidRectangle(_:));
- (nullable NSNumber *)isValidPointDictionary:(id)value error:(NSError **)error NS_SWIFT_NAME(isValidPoint(_:));
- (nullable NSNumber *)matchesValue:(nullable id)value expected:(NSString *)expected error:(NSError **)error NS_SWIFT_NAME(matches(_:expected:));
/** Only a value of the requested geometry type is returned. Unsupported values are ordinary absence. */
- (nullable FBAXOptionalValue<NSValue *> *)rectangleFromValue:(id)value error:(NSError **)error;
- (nullable FBAXOptionalValue<NSValue *> *)pointFromValue:(id)value error:(NSError **)error;
- (nullable FBAXOptionalValue<NSString *> *)descriptionOfValue:(nullable id)value error:(NSError **)error;
- (nullable FBAXOptionalValue<NSString *> *)localizedDescriptionOfError:(nullable NSError *)value error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
