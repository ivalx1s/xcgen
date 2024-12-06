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

struct ClonePackagesRecursively: ParsableCommand {
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
    
    func run() throws {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        let currentDirectoryURL = fileManager.currentDirectoryPath
        let fileURL = URL(fileURLWithPath: currentDirectoryURL).appendingPathComponent(jsonFilePath)
        let data = try Data(contentsOf: fileURL)
        
        var packageList: PackageList?
        do {
            packageList = try decoder.decode(PackageList.self, from: Data(contentsOf: fileURL))
        } catch {
            throw ParseError.cannotDecodePackageList
        }
        
        guard let packageList else {
            throw ParseError.packageListHasntBeenDecoded
        }
        
        var remotePackages = packageList.packages
            .filter {
                $0.value.path == nil &&
                $0.value.url != nil &&
                $0.value.version != nil
            }
        
        var checkedOutPackages: Set<Remote> = []
        
        while true {
            var enriched = false
            
            for var (packageName, remote) in remotePackages {
                guard !checkedOutPackages.contains(remote) else {
                    continue
                }
                print("\n🔄 Processing package: \(packageName)")
                
                let repositoryName = remote.url!.split(separator: "/").last!
                let folderName = repositoryName.replacingOccurrences(of: ".git", with: "")
                
                let repositorySupposedPath = fileManager.currentDirectoryPath.appending("/\(Self.repositoryBasePath)/\(folderName)")
                if !fileManager.fileExists(atPath: repositorySupposedPath) {
                    let cloneTask = Process()
                    cloneTask.launchPath = "/usr/bin/env"
                    cloneTask.arguments = ["git", "clone", remote.url!, "\(Self.repositoryBasePath)/\(folderName)"]
                    cloneTask.standardOutput = FileHandle.nullDevice
                    cloneTask.standardError = FileHandle.nullDevice
                    cloneTask.launch()
                    cloneTask.waitUntilExit()
                }
                
                // Fetch task
                let fetchTask = Process()
                fetchTask.launchPath = "/usr/bin/env"
                fetchTask.arguments = ["git", "fetch"]
                fetchTask.currentDirectoryPath = "\(Self.repositoryBasePath)/\(folderName)"
                fetchTask.standardOutput = FileHandle.nullDevice
                fetchTask.standardError = FileHandle.nullDevice
                fetchTask.launch()
                fetchTask.waitUntilExit()
                
                // Check the termination status of the pull task
                if fetchTask.terminationStatus == 0 {
                    print("⤵️  Successfully fetched latest changes from the repo")
                } else {
                    print("❗️ Failed to fetch changes from \(remote.url!) for package \(packageName). Error \(fetchTask.terminationStatus). Up-to-date state of the repo cannot be guranteed.")
                }
                
                let checkoutTask = Process()
                checkoutTask.launchPath = "/usr/bin/env"
                checkoutTask.arguments = ["git", "checkout", remote.version!]
                checkoutTask.currentDirectoryPath = "\(Self.repositoryBasePath)/\(folderName)"
                checkoutTask.standardOutput = FileHandle.nullDevice
                checkoutTask.standardError = FileHandle.nullDevice
                checkoutTask.launch()
                checkoutTask.waitUntilExit()
                if checkoutTask.terminationStatus == 0 {
                    print("#️⃣  Tag: \(remote.version!)")
                } else {
                    print("❗️ Could not checkout \(packageName), tag \(remote.version!). Check version tag and try again.")
                }
                
                
                
                let packageResolveTask = Process()
                packageResolveTask.launchPath = "/usr/bin/env"
                packageResolveTask.arguments = ["swift", "package", "resolve"]
                packageResolveTask.currentDirectoryPath = "\(Self.repositoryBasePath)/\(folderName)"
                packageResolveTask.standardOutput = FileHandle.nullDevice
                packageResolveTask.standardError = FileHandle.nullDevice
                packageResolveTask.launch()
                packageResolveTask.waitUntilExit()
                
                checkedOutPackages.insert(remote)
                
                let currentDirectoryURL = fileManager.currentDirectoryPath
                let fileURL = URL(fileURLWithPath: currentDirectoryURL)
                    .appendingPathComponent(Self.repositoryBasePath)
                    .appendingPathComponent("\(folderName)")
                    .appendingPathComponent("Package.resolved")
                
                guard let pinsSerialized = try? Data(contentsOf: fileURL) else {
                    // package resolve always succeeds
                    // if we cannot read from disk
                    // that means there are no package dependencies
                    continue
                }
                
                
                print("🔂 Extracting \(packageName) dependencies")
                if let packagePins = try? decoder.decode(PackageResolved.WithoutObjRoot.Pins.self, from: pinsSerialized) {
                    let dependencies = extractDependencies(from: packagePins)
                    if !dependencies.isEmpty {
                        enriched = true
                        for dependency in dependencies {
                            let package = Remote(url: dependency.url, version: dependency.version)
                            remotePackages[dependency.name] = package
                        }
                    }
                } else if let packageObjs = try? decoder.decode(PackageResolved.WithObjRoot.Root.self, from: pinsSerialized) {
                    let dependencies = extractDependencies(from: packageObjs)
                    if !dependencies.isEmpty {
                        enriched = true
                        for dependency in dependencies {
                            let package = Remote(url: dependency.url, version: dependency.version)
                            remotePackages[dependency.name] = package
                        }
                    }
                } else {
                    print("❗️ Could not deserialize Package.resolved, dependencies for \(packageName) have not been extracted")
                    continue
                }
            }
            
            if !enriched {
                print("\n✅ Finished")
                break
            }
        }
    }
    
}


func extractDependencies(from packageResolved: PackageResolved.WithoutObjRoot.Pins) -> [Dependency] {
    packageResolved.pins.map {
        // rethink approach, we have revisions in pins, which are more secure // 🟡
        Dependency(name: $0.identity, url: $0.location, version: $0.state.version)
    }
}

func extractDependencies(from packageResolved: PackageResolved.WithObjRoot.Root) -> [Dependency] {
    packageResolved.object.pins.map {
        // rethink approach, we have revisions in pins, which are more secure // 🟡
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
