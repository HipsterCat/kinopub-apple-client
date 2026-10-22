//
//  DevSessionMirrorTests.swift
//  KinoPubAppleClientTests
//
//  The shared debug session file must never take a half token, and the audit log
//  must never carry a token in clear.
//

import XCTest
import KinoPubBackend
@testable import KinoPub

#if DEBUG && (targetEnvironment(simulator) || os(macOS))
final class DevSessionMirrorTests: XCTestCase {

  /// Unit tests feed `AccessTokenServiceImpl` fake tokens; the shared session file must
  /// be out of their reach, or every test run signs out every debug build on the Mac.
  func testUnitTestsNeverReachTheSharedSessionFile() {
    XCTAssertNil(DevSessionMirror.fileURL)
    XCTAssertFalse(DevSessionMirror.exists)
    XCTAssertNil(DevSessionMirror.load())
  }

  func testOnlyACompleteTokenIsWritable() {
    XCTAssertTrue(DevSessionMirror.isComplete(AccessToken(accessToken: "a", refreshToken: "r", expiresIn: 1)))
    XCTAssertFalse(DevSessionMirror.isComplete(AccessToken(accessToken: "", refreshToken: "r", expiresIn: 1)))
    XCTAssertFalse(DevSessionMirror.isComplete(AccessToken(accessToken: "a", refreshToken: "", expiresIn: 1)))
  }

  func testTheLogCarriesFingerprintsNotTokens() {
    let token = AccessToken(accessToken: "access-secret-value", refreshToken: "refresh-secret-value", expiresIn: 3600)
    let line = DevSessionMirror.describe(token)

    XCTAssertFalse(line.contains("secret"), line)
    XCTAssertEqual(DevSessionMirror.fingerprint("refresh-secret-value").count, 8)
    XCTAssertEqual(DevSessionMirror.fingerprint("refresh-secret-value"),
                   DevSessionMirror.fingerprint("refresh-secret-value"))
    XCTAssertEqual(DevSessionMirror.fingerprint(""), "<empty>")
  }
}
#endif
