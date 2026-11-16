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
import ObjectiveC.runtime

/// A helper to bypass Pulse's swizzle on URLSessionTask resume methods.
/// This is used to call the original implementations directly, to avoid
/// issues with Pulse's swizzle on aggregate asset download tasks whose
/// `currentRequest` throws.
/// This mirrors the intent of similar logic in NetworkDiagnostics.swift.
public struct URLSessionResumeGuard {
    /// Returns the Objective-C methods for the `resume` selector on
    /// URLSessionTask and URLSessionDataTask if available, in that order,
    /// without duplicates.
    public static func resumeMethods() -> [Method] {
        let resumeSelector = #selector(URLSessionTask.resume)
        var methods: [Method] = []
        
        if let urlSessionTaskClass: AnyClass = NSClassFromString("NSURLSessionTask"),
           let method = class_getInstanceMethod(urlSessionTaskClass, resumeSelector) {
            methods.append(method)
        }

        if let urlSessionDataTaskClass: AnyClass = NSClassFromString("NSURLSessionDataTask"),
           let method = class_getInstanceMethod(urlSessionDataTaskClass, resumeSelector) {
            // Append only if not already included
            if !methods.contains(where: { method_getImplementation($0) == method_getImplementation(method) }) {
                methods.append(method)
            }
        }
        
        return methods
    }

    /// Reinstalls the original IMPs for the given methods.
    /// If the counts of methods and originals do not match, does nothing safely.
    public static func install(methods: [Method], originals: [IMP]) {
        guard methods.count == originals.count else { return }
        for (method, originalIMP) in zip(methods, originals) {
            method_setImplementation(method, originalIMP)
        }
    }

    /// Calls the original resume IMP on the given URLSessionTask.
    ///
    /// This is used to bypass Pulse's swizzle and call the original
    /// implementation directly.
    internal static func callOriginalResume(on task: URLSessionTask, originalIMP: IMP) {
        typealias ResumeFunction = @convention(c) (AnyObject, Selector) -> Void
        let function = unsafeBitCast(originalIMP, to: ResumeFunction.self)
        function(task, #selector(URLSessionTask.resume))
    }
}
