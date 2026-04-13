/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let ProcessMessage = "DLMessageProcessMessage"
private let DeviceReady = "DLMessageDeviceReady"

@objc(FBDeviceLinkClient)
public class FBDeviceLinkClient: NSObject {
  private let connection: FBAMDServiceConnection
  private let queue: DispatchQueue

  // MARK: Initializers

  @objc public static func deviceLinkClient(connection: FBAMDServiceConnection) -> FBFuture<FBDeviceLinkClient> {
    let queue = DispatchQueue(label: "com.facebook.fbdevicecontrol.fbdevicelinkclient")
    return
      (FBDeviceLinkClient.performVersionExchange(connection: connection, queue: queue)
      .onQueue(
        queue,
        map: { _ -> AnyObject in
          return FBDeviceLinkClient(connection: connection, queue: queue)
        })) as! FBFuture<FBDeviceLinkClient>
  }

  init(connection: FBAMDServiceConnection, queue: DispatchQueue) {
    self.connection = connection
    self.queue = queue
    super.init()
  }

  // MARK: Public Methods

  public func processMessage(_ message: Any) -> FBFuture<NSDictionary> {
    let connection = connection
    return FBFuture.onQueue(
      queue,
      resolveValue: { error in
        do {
          let result = try connection.sendAndReceiveMessage([ProcessMessage, message])
          guard let resultArray = result as? NSArray else {
            return FBDeviceControlError.describe("Result is not an NSArray: \(String(describing: result))").fail(error) as? NSDictionary
          }
          let responseType = resultArray[0]
          guard let responseString = responseType as? String else {
            return FBDeviceControlError.describe("\(responseType) is not an NSString in \(resultArray)").fail(error) as? NSDictionary
          }
          if responseString != ProcessMessage {
            return FBDeviceControlError.describe("\(responseString) should be a \(ProcessMessage)").fail(error) as? NSDictionary
          }
          guard let response = resultArray[1] as? NSDictionary else {
            return FBDeviceControlError.describe("\(resultArray[1]) is not a NSDictionary").fail(error) as? NSDictionary
          }
          return response
        } catch let caughtError {
          error?.pointee = caughtError as NSError
          return nil
        }
      }) as! FBFuture<NSDictionary>
  }

  // MARK: Private

  private static func performVersionExchange(connection: FBAMDServiceConnection, queue: DispatchQueue) -> FBFuture<NSNull> {
    return FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let plist = try connection.receiveMessage()
          guard let plistArray = plist as? NSArray else {
            return FBDeviceControlError.describe("\(String(describing: plist)) is not an array in version exchange").fail(errorPointer) as? NSNull
          }
          let versionNumber = plistArray[1]
          guard versionNumber is NSNumber else {
            return FBDeviceControlError.describe("\(versionNumber) is not a NSNumber for the handshake version").fail(errorPointer) as? NSNull
          }
          let response: [Any] = ["DLMessageVersionExchange", "DLVersionsOk", versionNumber]
          let reply = try connection.sendAndReceiveMessage(response)
          guard let replyArray = reply as? NSArray else {
            return FBDeviceControlError.describe("\(String(describing: reply)) is not an array in version exchange").fail(errorPointer) as? NSNull
          }
          let message = replyArray[0]
          guard let messageString = message as? String else {
            return FBDeviceControlError.describe("\(message) is not a NSString for the device ready call").fail(errorPointer) as? NSNull
          }
          if messageString != DeviceReady {
            return FBDeviceControlError.describe("\(messageString) is not equal to \(DeviceReady)").fail(errorPointer) as? NSNull
          }
          return NSNull()
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSNull>
  }
}
