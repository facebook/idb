/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let DefaultDRMHandshakeURL = "https://albert.apple.com/deviceservices/drmHandshake"
private let DefaultDeviceActivationURL = "https://albert.apple.com/deviceservices/deviceActivation"

@objc(FBDeviceActivationCommands)
public class FBDeviceActivationCommands: NSObject, FBDeviceActivationCommandsProtocol, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBDeviceActivationCommands Implementation

  public func activate() -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    let logger = device.logger
    return
      (activationState()
      .onQueue(
        device.asyncQueue,
        fmap: { activationState -> FBFuture<AnyObject> in
          if activationState as! FBDeviceActivationState == FBDeviceActivationState.activated {
            logger?.log("Device is already activated, nothing to activate")
            return FBFuture(result: NSNull() as AnyObject)
          }
          if activationState as! FBDeviceActivationState == FBDeviceActivationState.unactivated {
            logger?.log("Device is not activated, starting activation")
            return self.performActivation() as! FBFuture<AnyObject>
          }
          return FBControlCoreError.describe("\(activationState) is not a valid activation state").failFuture()
        })) as! FBFuture<NSNull>
  }

  // MARK: - Private

  private func confirmActivationState(_ activationState: FBDeviceActivationState) -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (self.activationState()
      .onQueue(
        device.asyncQueue,
        fmap: { actualActivationState -> FBFuture<AnyObject> in
          if activationState != (actualActivationState as! FBDeviceActivationState) {
            return FBControlCoreError.describe("Activation State \(activationState) is not equal to actual activation state \(actualActivationState)").failFuture()
          }
          return FBFuture(result: NSNull() as AnyObject)
        })) as! FBFuture<NSNull>
  }

  private func performActivation() -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    let logger = device.logger
    return
      (confirmActivationState(FBDeviceActivationState.unactivated)
      .onQueue(
        device.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          logger?.log("Building DRM Handshake Payload")
          return self.buildDRMHandshakePayload() as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        device.workQueue,
        fmap: { drmHandshakePayload -> FBFuture<AnyObject> in
          logger?.log("Obtaining Activation record from DRM Handshake Payload")
          return self.activationRecordFromDRMHandshakePayload(drmHandshakePayload as! Data) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        device.workQueue,
        fmap: { activationRecordPayload -> FBFuture<AnyObject> in
          logger?.log("Performing activation from activation record")
          return self.activateFromActivationRecord(activationRecordPayload as! Data) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        device.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          logger?.log("Confirming activation state is Activated")
          return self.confirmActivationState(FBDeviceActivationState.activated) as! FBFuture<AnyObject>
        })) as! FBFuture<NSNull>
  }

  private func mobileActivationService() -> FBFutureContext<FBAMDServiceConnection> {
    guard let device else {
      return FBDeviceControlError().describe("Device is nil").failFutureContext() as! FBFutureContext<FBAMDServiceConnection>
    }
    return device.startService("com.apple.mobileactivationd")
  }

  private func activationState() -> FBFuture<AnyObject> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      mobileActivationService()
      .onQueue(
        device.workQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            let response = try connection.sendAndReceiveMessage(["Command": "GetActivationStateRequest"])
            guard let responseDict = response as? NSDictionary,
              let activationState = responseDict["Value"] as? String
            else {
              return FBControlCoreError.describe("No Activation State in \(String(describing: response))").failFuture()
            }
            return FBFuture(result: FBDeviceActivationStateCoerceFromString(activationState) as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        })
  }

  private func buildDRMHandshakePayload() -> FBFuture<NSData> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (mobileActivationService()
      .onQueue(
        device.workQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            let response = try connection.sendAndReceiveMessage(["Command": "CreateTunnel1SessionInfoRequest"])
            guard let responseDict = response as? NSDictionary,
              let responsePayload = responseDict["Value"] as? [String: Any]
            else {
              return FBControlCoreError.describe("No 'Value' in \(String(describing: response))").failFuture()
            }
            return FBDeviceActivationCommands.mobileActivationRequest(forRequestPayload: responsePayload, queue: device.workQueue) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<NSData>
  }

  private func activationRecordFromDRMHandshakePayload(_ handshakePayload: Data) -> FBFuture<NSData> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (mobileActivationService()
      .onQueue(
        device.workQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            let response = try connection.sendAndReceiveMessage(["Command": "CreateTunnel1ActivationInfoRequest", "Value": handshakePayload])
            guard let responseDict = response as? NSDictionary,
              let responsePayload = responseDict["Value"] as? [String: Any]
            else {
              return FBControlCoreError.describe("No 'Value' in \(String(describing: response))").failFuture()
            }
            return FBDeviceActivationCommands.mobileActivationActivate(forRequestPayload: responsePayload, queue: device.workQueue) as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<NSData>
  }

  private func activateFromActivationRecord(_ activationRecord: Data) -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (mobileActivationService()
      .onQueue(
        device.workQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            _ = try connection.sendAndReceiveMessage(["Command": "HandleActivationInfoWithSessionRequest", "Value": activationRecord])
            return FBFuture(result: NSNull() as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<NSNull>
  }

  private static func mobileActivationRequest(forRequestPayload requestPayload: [String: Any], queue: DispatchQueue) -> FBFuture<NSData> {
    let body: Data
    do {
      body = try PropertyListSerialization.data(fromPropertyList: requestPayload, format: .xml, options: 0)
    } catch {
      return FBFuture(error: error)
    }

    let url = URL(string: ProcessInfo.processInfo.environment["IDB_DRM_HANDSHAKE_URL"] ?? DefaultDRMHandshakeURL)!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
    request.setValue("application/xml", forHTTPHeaderField: "Accept")
    request.setValue("idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/FBDeviceActivationCommands.m)", forHTTPHeaderField: "User-Agent")

    return
      (response(for: request)
      .onQueue(
        queue,
        fmap: { result -> FBFuture<AnyObject> in
          guard let resultArray = result as? NSArray,
            let httpResponse = resultArray[0] as? HTTPURLResponse,
            let responseData = resultArray[1] as? Data
          else {
            return FBControlCoreError.describe("Invalid response format").failFuture()
          }
          if httpResponse.statusCode != 200 {
            return FBControlCoreError.describe("\(httpResponse) no 200").failFuture()
          }
          do {
            _ = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)
          } catch {
            return FBFuture(error: error)
          }
          return FBFuture(result: responseData as NSData as AnyObject)
        })) as! FBFuture<NSData>
  }

  private static func mobileActivationActivate(forRequestPayload requestPayload: [String: Any], queue: DispatchQueue) -> FBFuture<NSData> {
    let payloadData: Data
    do {
      payloadData = try PropertyListSerialization.data(fromPropertyList: requestPayload, format: .xml, options: 0)
    } catch {
      return FBFuture(error: error)
    }

    // Multipart info
    let boundaryConstant = UUID().uuidString
    let contentType = "multipart/form-data; boundary=\(boundaryConstant)"

    let url = URL(string: ProcessInfo.processInfo.environment["IDB_ACTIVATION_URL"] ?? DefaultDeviceActivationURL)!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = multipartData(fromRequestPayload: payloadData, key: "activation-info", boundary: boundaryConstant)
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("idb (https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/FBDeviceActivationCommands.m)", forHTTPHeaderField: "User-Agent")

    return
      (response(for: request)
      .onQueue(
        queue,
        fmap: { result -> FBFuture<AnyObject> in
          guard let resultArray = result as? NSArray,
            let httpResponse = resultArray[0] as? HTTPURLResponse,
            let responseData = resultArray[1] as? Data
          else {
            return FBControlCoreError.describe("Invalid response format").failFuture()
          }
          if httpResponse.statusCode != 200 {
            return FBControlCoreError.describe("\(httpResponse) no 200").failFuture()
          }
          do {
            let responsePlist = try PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)
            guard let responseDict = responsePlist as? [String: Any],
              let activationRecord = responseDict["ActivationRecord"]
            else {
              return FBControlCoreError.describe("No 'ActivationRecord' in \(String(describing: responsePlist))").failFuture()
            }
            let activationRecordData = try PropertyListSerialization.data(fromPropertyList: activationRecord, format: .xml, options: 0)
            return FBFuture(result: activationRecordData as NSData as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<NSData>
  }

  private static func response(for request: URLRequest) -> FBFuture<AnyObject> {
    let future = FBMutableFuture<AnyObject>()
    let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
      if let error {
        future.resolveWithError(error)
        return
      }
      guard let responseData else {
        future.resolveWithError(FBControlCoreError.describe("No response data in response \(String(describing: response))").build())
        return
      }
      future.resolve(withResult: [response as Any, responseData] as AnyObject)
    }
    task.resume()
    return future
  }

  private static func multipartData(
    fromRequestPayload payload: Data,
    key: String,
    boundary: String
  ) -> Data {
    let dashesData = "--".data(using: .utf8)!
    let newlineData = "\r\n".data(using: .utf8)!
    let keyData = key.data(using: .utf8)!
    let boundaryData = boundary.data(using: .utf8)!
    let valueHeaderData = "Content-Disposition: form-data; name=".data(using: .utf8)!

    var data = Data()

    // Header prefixed with dashes.
    data.append(contentsOf: dashesData)
    data.append(contentsOf: boundaryData)
    data.append(contentsOf: newlineData)

    // Then the key-value
    data.append(contentsOf: valueHeaderData)
    data.append(contentsOf: keyData)
    data.append(contentsOf: newlineData)
    data.append(contentsOf: newlineData)
    data.append(contentsOf: payload)
    data.append(contentsOf: newlineData)

    // Then the trailer, suffixed with dashes
    data.append(contentsOf: dashesData)
    data.append(contentsOf: boundaryData)
    data.append(contentsOf: dashesData)
    data.append(contentsOf: newlineData)

    return data
  }
}
