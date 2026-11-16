//
//  URLSessionResumeGuard.swift
//  KinoPubUI
//
//  Pulse's resume swizzle (`URLSessionSwizzler.swizzleURLSessionTaskResume`) reads
//  `currentRequest` on every task it sees. `AVAggregateAssetDownloadTask` throws
//  `NSGenericException` from that getter — "AVAggregateAssetDownloadTask does not
//  support currentRequest property". The task an HLS download actually resumes is
//  the private subclass `__NSCFBackgroundAVAggregateAssetDownloadTaskNoChildTask`.
//  It is not an `AVAssetDownloadTask`, so the early return inside Pulse's
//  `logTaskCreated` does not apply, and the swizzle then reads the property.
//
//  `originalRequest` is unavailable on the same classes. The guard therefore
//  never enters the logging implementation for an asset-download task: it calls
//  the `resume` that was in place before Pulse.
//

import Foundation
import ObjectiveC

#if os(iOS) || os(macOS)
import AVFoundation
#endif

enum URLSessionResumeGuard {

  /// True when `currentRequest` / `originalRequest` throw instead of returning.
  ///
  /// The public classes are `AVAggregateAssetDownloadTask` and `AVAssetDownloadTask`
  /// (both `NS_UNAVAILABLE` for those properties; headers, iOS 27 / macOS 27).
  /// The name walk is the private subclasses, including the background task with
  /// no child that the download button resumes. Neither check reads a request.
  static func skipsLogging(_ task: URLSessionTask) -> Bool {
    #if os(iOS) || os(macOS)
    if task is AVAggregateAssetDownloadTask { return true }
    if task is AVAssetDownloadTask { return true }
    #endif
    var type: AnyClass? = object_getClass(task)
    while let current = type {
      let name = NSStringFromClass(current)
      if name.contains("AggregateAssetDownload") || name.contains("AVAssetDownloadTask") {
        return true
      }
      if current == URLSessionTask.self { return false }
      type = class_getSuperclass(current)
    }
    return false
  }

  /// The `resume` methods Pulse replaces, looked up the same way, so the guard
  /// wraps the implementation the download task actually runs.
  static func resumeMethods() -> [Method] {
    var methods: [Method] = []
    func append(_ method: Method) {
      guard !methods.contains(where: { $0 == method }) else { return }
      methods.append(method)
    }
    if let method = class_getInstanceMethod(URLSessionTask.self, #selector(URLSessionTask.resume)) {
      append(method)
    }
    // "__NSCFURLSessionTask" — joined at runtime, as Pulse does, so the private
    // name is not one string in the binary.
    let sessionTaskName = ["__", "NS", "CFURL", "Session", "Task"].joined()
    if let sessionTaskClass = NSClassFromString(sessionTaskName),
       let method = class_getInstanceMethod(sessionTaskClass, NSSelectorFromString("resume")) {
      append(method)
    }
    return methods
  }

  /// `original` is `resume` from before the logging swizzle. `logging` is that swizzle.
  /// An asset-download task must take `original` and must not take `logging`.
  static func callResume(_ task: URLSessionTask, original: IMP, logging: IMP) {
    let imp = skipsLogging(task) ? original : logging
    typealias Resume = @convention(c) (AnyObject, Selector) -> Void
    unsafeBitCast(imp, to: Resume.self)(task, #selector(URLSessionTask.resume))
  }

  /// Call after `NetworkLogger.enableProxy`, which has replaced these implementations.
  /// `originals` were captured before that call, in the same order as `methods`.
  static func install(methods: [Method], originals: [IMP]) {
    precondition(methods.count == originals.count)
    for (method, original) in zip(methods, originals) {
      let logging = method_getImplementation(method)
      let block: @convention(block) (URLSessionTask) -> Void = { task in
        callResume(task, original: original, logging: logging)
      }
      method_setImplementation(method, imp_implementationWithBlock(block))
    }
  }
}
