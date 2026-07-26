import Foundation

// Smoke test for DiskScanner + TreemapLayout.
// Run via scripts/run-smoke-tests.sh (it builds the fixture this expects).

var failures = 0
func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS: \(label)")
    } else {
        failures += 1
        print("FAIL: \(label)")
    }
}

let fixture = URL(fileURLWithPath: "/tmp/ts-test")
let semaphore = DispatchSemaphore(value: 0)

Task {
    // 1. Hidden files included, packages collapsed (defaults).
    var options = ScanOptions()
    options.includeHiddenFiles = true
    options.showPackageContents = false

    let result = try await DiskScanner(options: options).scan(url: fixture) { _ in }
    let root = result.root

    // a(1MB) + b(2MB) + c(0.5MB) + h(0.25MB) + x(0.125MB) = 3.875 MB logical
    let logical: Int64 = (1024 + 2048 + 512 + 256 + 128) * 1024
    check(root.size >= logical, "total size >= logical sum (\(root.size) vs \(logical))")
    check(root.size < logical + 500_000, "total size close to logical sum (allocation slack)")
    check(root.fileCount == 5, "fileCount == 5, got \(root.fileCount)")
    check(result.errorCount == 1, "1 unreadable dir recorded, got \(result.errorCount)")
    check(result.skippedPaths.first?.hasSuffix("noperm") == true, "skipped path is noperm")

    let names = (root.children ?? []).map(\.name).sorted()
    check(!names.contains("link"), "symlink not followed")
    check(names.contains(".hidden"), "hidden folder included")

    if let app = (root.children ?? []).first(where: { $0.name == "Fake.app" }) {
        check(app.kind == .package, "Fake.app detected as package")
        check(app.children == nil, "package collapsed to leaf")
        check(app.size >= 128 * 1024, "package size includes contents")
    } else {
        check(false, "Fake.app present in tree")
    }

    if let sub = (root.children ?? []).first(where: { $0.name == "sub" }) {
        check(sub.fileCount == 2, "sub fileCount == 2")
        check(sub.size >= (2048 + 512) * 1024, "sub size includes deep child")
        let deep = (sub.children ?? []).first(where: { $0.name == "deep" })
        check(deep?.parent === sub, "parent links wired")
        check(deep?.url.path == "/tmp/ts-test/sub/deep", "derived URL correct, got \(deep?.url.path ?? "nil")")
    } else {
        check(false, "sub present in tree")
    }

    check(result.largestFiles.count == 5, "5 largest leaves, got \(result.largestFiles.count)")
    check(result.largestFiles.first?.name == "b.bin", "largest is b.bin, got \(result.largestFiles.first?.name ?? "nil")")
    let sizes = result.largestFiles.map(\.size)
    check(sizes == sizes.sorted(by: >), "largest files sorted descending")

    // 2. Hidden files excluded.
    options.includeHiddenFiles = false
    let noHidden = try await DiskScanner(options: options).scan(url: fixture) { _ in }
    check(noHidden.root.fileCount == 4, "hidden excluded -> fileCount 4, got \(noHidden.root.fileCount)")

    // 3. Package contents shown.
    options.includeHiddenFiles = true
    options.showPackageContents = true
    let withPackages = try await DiskScanner(options: options).scan(url: fixture) { _ in }
    let app2 = (withPackages.root.children ?? []).first(where: { $0.name == "Fake.app" })
    check(app2?.children?.isEmpty == false, "package expanded when option on")

    // 4. Treemap layout invariants.
    let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
    let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
    let rects = TreemapLayout.layout(values: values, in: rect)
    check(rects.count == values.count, "treemap emits one rect per value")
    let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
    check(abs(area - 240_000) < 1, "treemap areas sum to rect area, got \(area)")
    for i in 0..<rects.count {
        for j in (i + 1)..<rects.count {
            let overlap = rects[i].intersection(rects[j])
            if overlap.width * overlap.height >= 0.01 {
                check(false, "rects \(i)/\(j) do not overlap")
            }
        }
    }
    check(true, "no treemap rects overlap")
    let ratio0 = Double(rects[0].width / rects[0].height)
    check(ratio0 > 0.2 && ratio0 < 5, "first cell aspect reasonable: \(ratio0)")

    // 5. Cancellation propagates.
    let cancelTask = Task { () -> Bool in
        do {
            _ = try await DiskScanner(options: options).scan(url: URL(fileURLWithPath: NSHomeDirectory())) { _ in }
            return false
        } catch is CancellationError {
            return true
        } catch {
            return false
        }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    cancelTask.cancel()
    let cancelled = await cancelTask.value
    check(cancelled, "cancellation throws CancellationError")

    print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILURES")
    semaphore.signal()
}

semaphore.wait()
exit(failures == 0 ? 0 : 1)
