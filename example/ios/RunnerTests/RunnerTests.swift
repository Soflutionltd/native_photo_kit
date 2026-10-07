import Flutter
import UIKit
import XCTest

// If your plugin has been explicitly set to "type: .dynamic" in the Package.swift,
// you will need to add your plugin as a dependency of RunnerTests within Xcode.

@testable import native_photo_kit

class RunnerTests: XCTestCase {

  func testUnknownMethodIsNotImplemented() {
    let plugin = NativePhotoKitPlugin()
    let call = FlutterMethodCall(methodName: "unknown", arguments: [String: Any]())

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue(result as AnyObject === FlutterMethodNotImplemented as AnyObject)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testEncodeJpegReturnsJpegBytes() {
    let plugin = NativePhotoKitPlugin()
    let rgba = Data(repeating: 200, count: 4 * 4 * 4)
    let call = FlutterMethodCall(
      methodName: "encodeJpeg",
      arguments: [
        "rgba": FlutterStandardTypedData(bytes: rgba),
        "width": 4,
        "height": 4,
        "quality": 90,
      ] as [String: Any])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      let jpeg = (result as? FlutterStandardTypedData)?.data
      XCTAssertEqual(jpeg?.prefix(2), Data([0xFF, 0xD8]))
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 5)
  }

}
