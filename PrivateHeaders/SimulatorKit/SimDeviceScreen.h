/**
 * ObjC-compatible interface for SimulatorKit.SimDeviceScreen (Swift class).
 *
 * ObjC runtime name: _TtC12SimulatorKit15SimDeviceScreen
 *
 * In Xcode 26.3+, SimDeviceScreen is the primary way to obtain a SimScreen
 * and its IOSurfaces.  The old ioPorts -> port descriptor path may return
 * empty or incompatible descriptors.
 */

#import <Foundation/Foundation.h>

@class SimDevice;

NS_ASSUME_NONNULL_BEGIN

@interface SimDeviceScreen : NSObject

- (nullable instancetype)initWithDevice:(SimDevice *)device screenID:(uint32_t)screenID;

/** Underlying CoreSimulator SimScreen protocol proxy. */
@property (nonatomic, readonly, nullable) id screen;

@property (nonatomic, readonly) uint32_t screenID;
@property (nonatomic, readonly) BOOL isDefault;
@property (nonatomic, readonly) BOOL isCarPlay;

@end

NS_ASSUME_NONNULL_END
