//
//  AVMCPBlockingWait.swift
//  AppView
//
//  Block background MCP threads until main-queue Rx work completes (sem, not spin).
//

import Foundation

enum AVMCPBlockingWait {
    /// Run `work` on main; block calling thread until `signal` or timeout.
    static func onMain<T>(
        timeout: TimeInterval,
        work: @escaping (@escaping (Result<T, Error>) -> Void) -> Void
    ) -> Result<T, Error> {
        if Thread.isMainThread {
            fatalError("AVMCPBlockingWait.onMain must not run on main thread")
        }
        let sem = DispatchSemaphore(value: 0)
        var outcome: Result<T, Error>?
        DispatchQueue.main.async {
            sem.signal()
            work { result in
                outcome = result
                sem.signal()
            }
        }
        let hopOk = sem.wait(timeout: .now() + AVMCPTiming.mainQueueHop) == .success
        guard hopOk else {
            return .failure(AVAppViewClientErrors.inner)
        }
        let waitOk = sem.wait(timeout: .now() + timeout) == .success
        if let outcome { return outcome }
        if waitOk {
            return .failure(AVAppViewClientErrors.inner)
        }
        return .failure(AVAppViewClientErrors.timeout())
    }
}
