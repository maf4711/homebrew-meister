// purge.js — JavaScript-for-Automation helper for `meister purge` (macOS only).
//   volume <path>         prints "<important-usage-free> <free> <total>" in bytes
//   check  <label>        reads NUL-separated paths on stdin, counts evictable items
//   evict  <label>        same, but asks iCloud to remove the local copies
// check/evict print "ok=<n> bytes=<b> failed=<n> skipped=<n>".
// With PURGE_PROGRESS=1, progress lines go to stderr (eviction can take an hour).
// An item is only evicted when iCloud reports it as fully downloaded AND uploaded,
// so nothing that exists only on this Mac is ever touched.
ObjC.import("Foundation");

function vals(path, keys) {
  if (!path) return null;
  var url = $.NSURL.fileURLWithPath(path);
  if (url.isNil()) return null;
  var err = $();
  var r = url.resourceValuesForKeysError(keys, err);
  return r.isNil() ? null : ObjC.deepUnwrap(r);
}

function run(argv) {
  var mode = argv[0];
  if (mode === "volume") {
    var v = vals(argv[1], ["NSURLVolumeAvailableCapacityForImportantUsageKey", "NSURLVolumeAvailableCapacityKey", "NSURLVolumeTotalCapacityKey"]);
    if (!v || v.NSURLVolumeAvailableCapacityKey === undefined) throw new Error("volume capacity unreadable: " + argv[1]);
    return [v.NSURLVolumeAvailableCapacityForImportantUsageKey, v.NSURLVolumeAvailableCapacityKey, v.NSURLVolumeTotalCapacityKey].join(" ");
  }
  if (mode !== "check" && mode !== "evict") throw new Error("usage: purge.js volume|check|evict");

  var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
  var text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)) || "";
  var paths = text.split("\u0000").filter(function (p) { return p.length > 0; });

  // Files inside a package (.pages, .key, .rtfd …) are evicted as the whole package.
  var isPkg = {};
  function outermostPackage(path) {
    var parts = path.split("/"), found = null;
    for (var i = parts.length - 1; i > 1; i--) {
      var dir = parts.slice(0, i).join("/");
      if (!(dir in isPkg)) { var r = vals(dir, ["NSURLIsPackageKey"]); isPkg[dir] = !!(r && r.NSURLIsPackageKey); }
      if (isPkg[dir]) found = dir;
    }
    return found;
  }

  var sizes = {}, order = [];
  paths.forEach(function (p) {
    var r = vals(p, ["NSURLFileSizeKey"]);
    var target = outermostPackage(p) || p;
    if (!(target in sizes)) { sizes[target] = 0; order.push(target); }
    sizes[target] += (r && r.NSURLFileSizeKey) || 0;
  });

  var env = ObjC.deepUnwrap($.NSProcessInfo.processInfo.environment) || {};
  var progress = env.PURGE_PROGRESS === "1";
  var stderr = $.NSFileHandle.fileHandleWithStandardError;
  var lastReport = 0;
  function report(done, force) {
    if (!progress || order.length === 0) return;
    var now = Date.now();
    if (!force && now - lastReport < 10000) return;
    lastReport = now;
    var line = "      " + (mode === "evict" ? "evicting" : "checking") + " " + done + "/" + order.length +
      " items, " + (bytes / 1e9).toFixed(1) + " GB so far\n";
    stderr.writeData($.NSString.alloc.initWithUTF8String(line).dataUsingEncoding($.NSUTF8StringEncoding));
  }

  var fm = $.NSFileManager.defaultManager;
  var ok = 0, bytes = 0, failed = 0, skipped = 0;
  report(0, true);
  order.forEach(function (t, i) {
    report(i, false);
    var r = vals(t, ["NSURLIsUbiquitousItemKey", "NSURLUbiquitousItemDownloadingStatusKey", "NSURLUbiquitousItemIsUploadedKey", "NSURLUbiquitousItemIsExcludedFromSyncKey"]);
    if (!r || r.NSURLIsUbiquitousItemKey !== true || r.NSURLUbiquitousItemIsExcludedFromSyncKey === true ||
        r.NSURLUbiquitousItemDownloadingStatusKey !== "NSURLUbiquitousItemDownloadingStatusCurrent" ||
        r.NSURLUbiquitousItemIsUploadedKey !== true) { skipped++; return; }
    if (mode === "evict") {
      var err = $();
      if (!fm.evictUbiquitousItemAtURLError($.NSURL.fileURLWithPath(t), err)) { failed++; return; }
    }
    ok++; bytes += sizes[t];
  });
  report(order.length, true);
  return "ok=" + ok + " bytes=" + bytes + " failed=" + failed + " skipped=" + skipped;
}
