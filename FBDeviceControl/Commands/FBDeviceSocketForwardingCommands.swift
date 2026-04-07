// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceSocketForwardingCommands)
public class FBDeviceSocketForwardingCommands: NSObject, FBSocketForwardingCommands {
  private(set) weak var device: FBDevice?

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceSocketForwardingCommands(device: target as! FBDevice), to: self)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: FBSocketForwardingCommands Implementation

  public func drainLocalFileInput(
    _ localFileDescriptorInput: Int32,
    localFileOutput localFileDescriptorOutput: Int32,
    remotePort: Int32
  ) -> FBFuture<NSNull> {
    var error: NSError?
    let localConsumer = FBFileWriter.asyncWriter(withFileDescriptor: localFileDescriptorOutput, closeOnEndOfFile: false, error: &error)
    guard let localConsumer else {
      return FBFuture(error: error!)
    }
    return consumer(forRemotePort: Int(remotePort), writingTo: localConsumer).onQueue(
      device!.asyncQueue,
      pop: { remoteConsumer -> FBFuture<AnyObject> in
        let reader = FBFileReader.reader(withFileDescriptor: localFileDescriptorInput, closeOnEndOfFile: false, consumer: remoteConsumer, logger: nil)
        return reader.startReading().onQueue(
          self.device!.asyncQueue,
          map: { _ in
            reader.finishedReading
          })
      }) as! FBFuture<NSNull>
  }

  // MARK: Private

  private func consumer(forRemotePort remotePort: Int, writingTo consumer: any FBDataConsumer) -> FBFutureContext<any FBDataConsumer> {
    localSocketFromRemotePort(remotePort: remotePort).onQueue(
      device!.asyncQueue,
      pend: { (remoteSocket: NSNumber) -> FBFuture<AnyObject> in
        var error: NSError?
        let writer = FBFileWriter.asyncWriter(withFileDescriptor: remoteSocket.int32Value, closeOnEndOfFile: false, error: &error)
        guard let writer else {
          return FBFuture(error: error!)
        }
        let reader = FBFileReader.reader(withFileDescriptor: remoteSocket.int32Value, closeOnEndOfFile: false, consumer: consumer, logger: nil)
        return reader.startReading().mapReplace(writer)
      }) as! FBFutureContext<any FBDataConsumer>
  }

  private func localSocketFromRemotePort(remotePort: Int) -> FBFutureContext<NSNumber> {
    let logger = device?.logger
    return device!.connectToDevice(withPurpose: "Socket Connection").onQueue(
      device!.workQueue,
      pend: { (device: any FBDeviceCommands) -> FBFuture<AnyObject> in
        guard let getConnectionID = device.calls.GetConnectionID else {
          return FBDeviceControlError.describe("GetConnectionID not available").failFuture()
        }
        let connectionID = getConnectionID(device.amDeviceRef)
        if connectionID <= 0 {
          return FBDeviceControlError.describe("Failed to get ConnectionID from Device").failFuture()
        }
        logger?.log("Got connection ID \(connectionID), for device. Connecting to remote port \(remotePort)")
        var localSocket: Int32 = 0
        guard let usbMuxConnect = device.calls.USBMuxConnectByPort else {
          return FBDeviceControlError.describe("USBMuxConnectByPort not available").failFuture()
        }
        let status = usbMuxConnect(connectionID, Int32(UInt16(remotePort).bigEndian), &localSocket)
        if status != 0 {
          return FBDeviceControlError.describe("Failed to connect to remote port \(remotePort)").failFuture()
        }
        logger?.log("Got local socket \(localSocket) for remote port \(remotePort)")
        return FBFuture(result: NSNumber(value: localSocket) as AnyObject)
      }
    ).onQueue(
      device!.asyncQueue,
      contextualTeardown: { (localSocketNumber, _) -> FBFuture<NSNull> in
        logger?.log("Closing local socket \(localSocketNumber)")
        close((localSocketNumber as! NSNumber).int32Value)
        return FBFuture<NSNull>.empty()
      }) as! FBFutureContext<NSNumber>
  }
}
