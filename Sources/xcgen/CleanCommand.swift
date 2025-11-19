import Foundation
import ArgumentParser

struct CleanCaches: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Delete DerivedData, SwiftPM, and XcodeGen caches.",
        discussion: "Targets: all | dd | spm | xc."
    )

    @Argument(help: "Which caches to remove (all, dd, spm, or xc).")
    var target: CleanTarget

    func run() throws {
        CacheCleaner().clean(target: target)
    }
}

struct CacheCleaner {
    private let fileManager = FileManager.default

    func clean(target: CleanTarget) {
        print(target.startMessage)
        let directories = target.directories(within: fileManager.homeDirectoryForCurrentUser)
        for directory in directories {
            removeDirectoryIfNeeded(directory)
        }
        print("✅ Done")
    }

    private func removeDirectoryIfNeeded(_ directory: CacheDirectory) {
        let path = directory.url.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            print("ℹ️  Skipping \(directory.label) (\(path)) – not found")
            return
        }
        guard isDirectory.boolValue else {
            print("ℹ️  Skipping \(directory.label) (\(path)) – not a directory")
            return
        }
        do {
            try fileManager.removeItem(at: directory.url)
            print("🗑  Removed \(directory.label) (\(path))")
        } catch {
            print("❗️ Failed to remove \(directory.label) (\(path)): \(error.localizedDescription)")
        }
    }
}

struct CacheDirectory {
    let label: String
    let url: URL
}

enum CleanTarget: String, CaseIterable, ExpressibleByArgument {
    case all
    case dd
    case spm
    case xc

    static var allValueStrings: [String] {
        CleanTarget.allCases.map { $0.rawValue }
    }

    var startMessage: String {
        switch self {
        case .all:
            return "⚙️ Cleaning Xcode, SwiftPM, and XcodeGen caches..."
        case .dd:
            return "⚙️ Cleaning DerivedData..."
        case .spm:
            return "⚙️ Cleaning SwiftPM caches..."
        case .xc:
            return "⚙️ Cleaning Xcode caches..."
        }
    }

    func directories(within homeDirectory: URL) -> [CacheDirectory] {
        let derivedData = CacheDirectory(
            label: "DerivedData",
            url: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Developer")
                .appendingPathComponent("Xcode")
                .appendingPathComponent("DerivedData", isDirectory: true)
        )
        let xcodeCache = CacheDirectory(
            label: "Xcode cache",
            url: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Caches")
                .appendingPathComponent("com.apple.dt.Xcode", isDirectory: true)
        )
        let spmConfigCache = CacheDirectory(
            label: "SwiftPM configuration",
            url: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("org.swift.swiftpm", isDirectory: true)
        )
        let spmCache = CacheDirectory(
            label: "SwiftPM cache",
            url: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Caches")
                .appendingPathComponent("org.swift.swiftpm", isDirectory: true)
        )
        let xcodegenCache = CacheDirectory(
            label: "XcodeGen cache",
            url: homeDirectory
                .appendingPathComponent(".xcodegen")
                .appendingPathComponent("cache", isDirectory: true)
        )

        let directories: [CacheDirectory]
        switch self {
        case .dd:
            directories = [derivedData]
        case .spm:
            directories = [spmConfigCache, spmCache]
        case .xc:
            directories = [derivedData, xcodeCache]
        case .all:
            directories = [derivedData, xcodeCache, spmConfigCache, spmCache, xcodegenCache]
        }
        var seen: Set<String> = []
        return directories.filter { directory in
            let path = directory.url.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }
}
