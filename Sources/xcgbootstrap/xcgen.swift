import Foundation
import ArgumentParser

struct PackageList: Decodable {
    var packages: [String: Remote]
}

struct PackageListPipeline: Decodable {
    var packages: [String: RemoteTracked]
}

struct Remote: Decodable, Hashable {
    let url: String?
    let version: String?
    let path: String?
    
    init(
        url: String? = nil,
        version: String? = nil,
        path: String? = nil
    ) {
        self.url = url
        self.version = version
        self.path = path
    }
}

struct RemoteTracked: Decodable {
    let url: String
    let version: String
    var checkoutAttempted: Bool
}

enum ParseError: Error {
    case cannotDecodePackageList
    case packageListHasntBeenDecoded
}

@main
struct ClonePackagesCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: """
        The xcgbootstrap is a command-line utility that facilitates the initial setup of your xcodegen-powered projects.
        It streamlines your workflow by interpreting the project manifest, extracting project dependencies,
        and cloning these into the relevant directory alongside your main project.
        This tool also ensures you're working with the right dependency versions by checking out the corresponding version tags.
        """,
        subcommands: [
            ClonePackagesRecursively.self
        ]
    )
}

struct ClonePackagesRecursively: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submodules",
        abstract: """
        The 'submodules' command triggers the setup process.
        """,
        shouldDisplay: true
    )
    
    static let repositoryBasePath = "../Packages"
    
    @Argument(help: "Path to the json file containing information about packages")
    var jsonFilePath: String
    
    func run() async throws {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        let currentDirectoryURL = fileManager.currentDirectoryPath
        let fileURL = URL(fileURLWithPath: currentDirectoryURL).appendingPathComponent(jsonFilePath)
        let data = try Data(contentsOf: fileURL)
        
        var packageList: PackageList?
        do {
            packageList = try decoder.decode(PackageList.self, from: data)
        } catch {
            throw ParseError.cannotDecodePackageList
        }
        
        guard let packageList else {
            throw ParseError.packageListHasntBeenDecoded
        }
        
        let initialPackages = packageList.packages
            .filter {
                $0.value.path == nil &&
                $0.value.url != nil &&
                $0.value.version != nil
            }
        
        let packageManager = PackageManager(
            remotePackages: Dictionary(uniqueKeysWithValues: initialPackages.map { (key: $0.key, value: $0.value) }),
            checkedOutPackages: []
        )
        
        // Process everything concurrently in a single task group
        try await withThrowingTaskGroup(of: (String, [Dependency])?.self) { group in
            // Add initial packages to the group
            let toProcess = await packageManager.packagesToProcess()
            for (packageName, remote) in toProcess {
                group.addTask {
                    let deps = try await processPackage(
                        name: packageName,
                        remote: remote,
                        basePath: Self.repositoryBasePath,
                        decoder: decoder
                    )
                    return (packageName, deps)
                }
            }
            
            // Dynamically add discovered dependencies as they are found
            for try await result in group {
                guard let (packageName, dependencies) = result else { continue }
                
                // Mark the current package as checked out
                await packageManager.markCheckedOut(packageName)
                
                // Add new dependencies if any
                if !dependencies.isEmpty {
                    let newDeps = await packageManager.addDependencies(dependencies)
                    for (depName, depRemote) in newDeps {
                        group.addTask {
                            let deps = try await processPackage(
                                name: depName,
                                remote: depRemote,
                                basePath: Self.repositoryBasePath,
                                decoder: decoder
                            )
                            return (depName, deps)
                        }
                    }
                }
            }
        }
        
        print("\n✅ Finished")
    }
}

/// Actor responsible for managing the shared state related to package processing.
actor PackageManager {
    private var remotePackages: [String: Remote]
    private var checkedOutPackages: Set<Remote>
    
    init(remotePackages: [String: Remote], checkedOutPackages: Set<Remote>) {
        self.remotePackages = remotePackages
        self.checkedOutPackages = checkedOutPackages
    }
    
    func packagesToProcess() -> [(String, Remote)] {
        remotePackages.filter { !checkedOutPackages.contains($0.value) }.map { ($0.key, $0.value) }
    }
    
    func markCheckedOut(_ packageName: String) {
        if let remote = remotePackages[packageName] {
            checkedOutPackages.insert(remote)
        }
    }
    
    /// Adds newly discovered dependencies to the list of remote packages, filtering out duplicates and already checked out packages.
    /// Returns only those packages that are newly added and not yet checked out.
    func addDependencies(_ dependencies: [Dependency]) -> [(String, Remote)] {
        var newlyAdded: [(String, Remote)] = []
        for dep in dependencies {
            let pkg = Remote(url: dep.url, version: dep.version)
            if !remotePackages.keys.contains(dep.name) && !checkedOutPackages.contains(pkg) {
                remotePackages[dep.name] = pkg
                newlyAdded.append((dep.name, pkg))
            }
        }
        return newlyAdded
    }
}

/// Process a single package: clone if needed, fetch, checkout, resolve dependencies, and extract them.
///
/// Returns the list of newly discovered dependencies.
private func processPackage(name: String,
                            remote: Remote,
                            basePath: String,
                            decoder: JSONDecoder) async throws -> [Dependency] {
    guard let remoteURL = remote.url, let version = remote.version else {
        return []
    }
    print("\n🔄 Processing package: \(name)")
    
    let folderName = remoteURL.split(separator: "/").last!.replacingOccurrences(of: ".git", with: "")
    let fileManager = FileManager.default
    let repositorySupposedPath = fileManager.currentDirectoryPath.appending("/\(basePath)/\(folderName)")
    
    // Clone if needed
    if !fileManager.fileExists(atPath: repositorySupposedPath) {
        try await runCommand(["git", "clone", remoteURL, "\(basePath)/\(folderName)"])
    }
    
    // Fetch task
    let fetchStatus = try await runCommand(["git", "fetch"], directory: "\(basePath)/\(folderName)")
    if fetchStatus == 0 {
        print("⤵️  Successfully fetched latest changes from the repo: \(name)")
    } else {
        print("❗️ Failed to fetch changes from \(remoteURL) for package \(name). Error \(fetchStatus). Up-to-date state of the repo cannot be guaranteed.")
    }
    
    // Checkout the correct version
    let checkoutStatus = try await runCommand(["git", "checkout", version], directory: "\(basePath)/\(folderName)")
    if checkoutStatus == 0 {
        print("#️⃣  Checked out tag: \(version) for \(name)")
    } else {
        print("❗️ Could not checkout \(name), tag \(version). Check version tag and/or url and try again.")
    }
    
    // Resolve dependencies
    _ = try await runCommand(["swift", "package", "resolve"], directory: "\(basePath)/\(folderName)")
    
    let pinsURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        .appendingPathComponent(basePath)
        .appendingPathComponent(folderName)
        .appendingPathComponent("Package.resolved")
    
    guard let pinsSerialized = try? Data(contentsOf: pinsURL) else {
        // No package dependencies
        return []
    }
    
    print("🔂 Extracting \(name) dependencies")
    if let packagePins = try? decoder.decode(PackageResolved.WithoutObjRoot.Pins.self, from: pinsSerialized) {
        return extractDependencies(from: packagePins)
    } else if let packageObjs = try? decoder.decode(PackageResolved.WithObjRoot.Root.self, from: pinsSerialized) {
        return extractDependencies(from: packageObjs)
    } else {
        print("❗️ Could not deserialize Package.resolved, dependencies for \(name) have not been extracted")
        return []
    }
}

/// Runs a command asynchronously and returns its termination status.
private func runCommand(_ arguments: [String], directory: String? = nil) async throws -> Int32 {
    return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = arguments
        if let directory = directory {
            process.currentDirectoryPath = directory
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        process.terminationHandler = { proc in
            continuation.resume(returning: proc.terminationStatus)
        }
        
        do {
            try process.run()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

func extractDependencies(from packageResolved: PackageResolved.WithoutObjRoot.Pins) -> [Dependency] {
    packageResolved.pins.map {
        Dependency(name: $0.identity, url: $0.location, version: $0.state.version)
    }
}

func extractDependencies(from packageResolved: PackageResolved.WithObjRoot.Root) -> [Dependency] {
    packageResolved.object.pins.map {
        Dependency(name: $0.package, url: $0.repositoryURL, version: $0.state.version)
    }
}

struct Dependency {
    var name: String
    var url: String
    var version: String
}

extension String {
    func firstIndex(of substring: String) -> String.Index? {
        if let range = self.range(of: substring) {
            return range.lowerBound
        }
        return nil
    }
}
