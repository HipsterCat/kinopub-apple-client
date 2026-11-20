//
//  URLSessionResumeGuardTests.swift
//
//  After Pulse's `enableProxy`, `install` puts the pre-Pulse `resume` IMPs
//  back. Every task uses those originals — aggregate / asset-download tasks
//  throw from `currentRequest` if they ever enter the swizzle.
//

import XCTest
import ObjectiveC
@testable import KinoPubUI

#if os(iOS) || os(macOS)
import AVFoundation
#endif

final class URLSessionResumeGuardTests: XCTestCase {

  /// `install` restores `originals` on every method. Data tasks and
  /// aggregate-named tasks both hit the original, never the logging IMP.
  func testInstallRestoresOriginalsForEveryTask() {
    let methods = URLSessionResumeGuard.resumeMethods()
    XCTAssertFalse(methods.isEmpty)
    let saved = methods.map { method_getImplementation($0) }
    defer {
      for (method, imp) in zip(methods, saved) {
        method_setImplementation(method, imp)
      }
    }

    let logging = Calls()
    let original = Calls()
    for method in methods {
      method_setImplementation(method, countingIMP(logging))
    }
    URLSessionResumeGuard.install(
      methods: methods,
      originals: Array(repeating: countingIMP(original), count: methods.count))

    let reads = RequestReads()
    let aggregate = probeTask(superklass: URLSessionTask.self,
                              name: "KPInstalledAggregateAssetDownloadTask",
                              reads: reads)
    aggregate.resume()
    XCTAssertEqual(logging.count, 0, "the logging swizzle reads currentRequest")
    XCTAssertGreaterThan(original.count, 0)
    XCTAssertEqual(reads.current, 0)
    XCTAssertEqual(reads.original, 0)

    let data = URLSession.shared.dataTask(with: URL(string: "https://example.invalid/kinopub-installed-resume")!)
    let originalAfterAggregate = original.count
    data.resume()
    XCTAssertEqual(logging.count, 0)
    XCTAssertGreaterThan(original.count, originalAfterAggregate)
    data.cancel()
  }

  func testPrivateAggregateClassResumeDoesNotReadTheRequest() {
    let reads = RequestReads()
    let task = probeTask(superklass: URLSessionTask.self,
                         name: "KPBackgroundAVAggregateAssetDownloadTaskNoChild",
                         reads: reads)
    assertOriginalResumeDoesNotRead(task, reads: reads)
  }

  #if os(iOS) || os(macOS)
  func testAggregateAssetDownloadTaskResumeDoesNotReadTheRequest() {
    let reads = RequestReads()
    let task = probeTask(superklass: AVAggregateAssetDownloadTask.self,
                         name: "KPAggregateAssetDownloadProbe",
                         reads: reads)
    assertOriginalResumeDoesNotRead(task, reads: reads)
  }

  func testAssetDownloadTaskResumeDoesNotReadTheRequest() {
    let reads = RequestReads()
    let task = probeTask(superklass: AVAssetDownloadTask.self,
                         name: "KPAssetDownloadProbe",
                         reads: reads)
    assertOriginalResumeDoesNotRead(task, reads: reads)
  }
  #endif

  private func assertOriginalResumeDoesNotRead(_ task: URLSessionTask, reads: RequestReads) {
    let methods = URLSessionResumeGuard.resumeMethods()
    XCTAssertFalse(methods.isEmpty)
    let saved = methods.map { method_getImplementation($0) }
    defer {
      for (method, imp) in zip(methods, saved) {
        method_setImplementation(method, imp)
      }
    }
    let original = Calls()
    let logging = Calls()
    for method in methods {
      method_setImplementation(method, countingIMP(logging))
    }
    URLSessionResumeGuard.install(
      methods: methods,
      originals: Array(repeating: countingIMP(original), count: methods.count))
    task.resume()
    XCTAssertEqual(logging.count, 0, "the logging swizzle reads currentRequest")
    XCTAssertEqual(original.count, 1)
    XCTAssertEqual(reads.current, 0)
    XCTAssertEqual(reads.original, 0)
  }
}

private final class Calls: @unchecked Sendable {
  var count = 0
}

private final class RequestReads: @unchecked Sendable {
  var current = 0
  var original = 0
}

private func countingIMP(_ calls: Calls) -> IMP {
  let block: @convention(block) (AnyObject) -> Void = { _ in
    calls.count += 1
  }
  return imp_implementationWithBlock(block)
}

/// A task whose request getters record a read. `class_createInstance` is left
/// unreleased: dealloc of an object that never ran `init` is its own crash.
private func probeTask(superklass: AnyClass, name: String, reads: RequestReads) -> URLSessionTask {
  let cls: AnyClass
  if let existing = NSClassFromString(name) {
    cls = existing
  } else {
    guard let pair = objc_allocateClassPair(superklass, name, 0) else {
      fatalError("could not subclass \(superklass) as \(name)")
    }
    let current: @convention(block) (AnyObject) -> AnyObject? = { _ in
      reads.current += 1
      return nil
    }
    let original: @convention(block) (AnyObject) -> AnyObject? = { _ in
      reads.original += 1
      return nil
    }
    let currentAdded = class_addMethod(pair, #selector(getter: URLSessionTask.currentRequest),
                                       imp_implementationWithBlock(current), "@@:")
    let originalAdded = class_addMethod(pair, #selector(getter: URLSessionTask.originalRequest),
                                        imp_implementationWithBlock(original), "@@:")
    precondition(currentAdded && originalAdded, "request getters were not overridden on \(name)")
    objc_registerClassPair(pair)
    cls = pair
  }
  guard let instance = class_createInstance(cls, 0) else {
    fatalError("could not allocate \(name)")
  }
  return instance as! URLSessionTask
}
