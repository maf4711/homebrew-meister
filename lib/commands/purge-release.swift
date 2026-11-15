// purge-release.swift — helper for `meister purge --do` (macOS only).
//   swift purge-release.swift <volume> <bytes> [timeout-seconds]
// Asks the macOS purge service (CacheDelete, the same service tmutil uses to thin
// snapshots) to release up to <bytes> of what Finder counts as purgeable.
// macOS decides what goes. Prints "released=<bytes>" as reported by the service.
// The call is asynchronous with a completion block, which is why this is not in purge.js.
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let amount = Int64(args[2]), amount > 0 else {
    FileHandle.standardError.write("usage: purge-release.swift <volume> <bytes> [timeout-seconds]\n".data(using: .utf8)!)
    exit(2)
}
let timeout = args.count > 3 ? (Double(args[3]) ?? 900) : 900
guard let handle = dlopen("/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete", RTLD_NOW),
      let symbol = dlsym(handle, "CacheDeletePurgeSpaceWithInfo") else {
    FileHandle.standardError.write("macOS purge service unavailable\n".data(using: .utf8)!)
    exit(1)
}
typealias Completion = @convention(block) (CFDictionary?) -> Void
typealias Purge = @convention(c) (CFDictionary, @escaping Completion) -> Void
let purge = unsafeBitCast(symbol, to: Purge.self)
let info: [String: Any] = ["CACHE_DELETE_VOLUME": args[1], "CACHE_DELETE_URGENCY": 4, "CACHE_DELETE_AMOUNT": amount]
let finished = DispatchSemaphore(value: 0)
var released: Int64?
purge(info as CFDictionary) { result in
    released = ((result as? [String: Any])?["CACHE_DELETE_AMOUNT"] as? NSNumber)?.int64Value
    finished.signal()
}
if finished.wait(timeout: .now() + timeout) == .timedOut {
    print("released=timeout")
    exit(3)
}
print("released=\(released.map(String.init) ?? "unknown")")
