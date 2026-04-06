// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

private let StartCommand: UInt32 = 0x00000000

@objc(FBDeviceLocationCommands)
public class FBDeviceLocationCommands: NSObject, FBLocationCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBLocationCommands

  public func overrideLocation(withLongitude longitude: Double, latitude: Double) -> FBFuture<NSNull> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (device
      .ensureDeveloperDiskImageIsMounted()
      .onQueue(
        device.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          return (device.startService("com.apple.dt.simulatelocation") as FBFutureContext<FBAMDServiceConnection>)
            .onQueue(
              device.workQueue,
              pop: { connection -> FBFuture<AnyObject> in
                do {
                  var start = StartCommand
                  let startData = Data(bytes: &start, count: MemoryLayout<UInt32>.size)
                  try connection.send(startData)

                  let latitudeString = "\(latitude)"
                  let latitudeData = latitudeString.data(using: .utf8)!
                  try connection.send(withLengthHeader: latitudeData)

                  let longitudeString = "\(longitude)"
                  let longitudeData = longitudeString.data(using: .utf8)!
                  try connection.send(withLengthHeader: longitudeData)

                  return FBFuture(result: NSNull() as AnyObject)
                } catch {
                  return FBFuture(error: error)
                }
              })
        })) as! FBFuture<NSNull>
  }
}
