import Foundation
import ArgumentParser

struct PackageList: Decodable {
	var packages: [String: Remote]
}

struct PackageListPipeline: Decodable {
	var packages: [String: RemoteTracked]
}

struct Remote: Decodable, Hashable {
	let url: String
	let version: String
}

struct RemoteTracked: Decodable {
	let url: String
	let version: String
	var checkoutAttempted: Bool
}

@main
struct ClonePackagesCLI: ParsableCommand {
	
	static let configuration = CommandConfiguration(
		abstract: "A brief description of my command-line tool",
		subcommands: [
			ClonePackagesRecursively.self
		]
	)
}

struct ClonePackagesRecursively: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "submodules",
		abstract: "A brief description of submodules",
		shouldDisplay: true
	)
	
	static let repositoryBasePath = "repositories"
	
	@Argument(help: "Path to the json file containing information about packages")
	var jsonFilePath: String
	
	func run() throws {
		let fileManager = FileManager.default
		let decoder = JSONDecoder()
		let currentDirectoryURL = fileManager.currentDirectoryPath
		let fileURL = URL(fileURLWithPath: currentDirectoryURL).appendingPathComponent(jsonFilePath)
		let data = try Data(contentsOf: fileURL)
		
		var packageList: PackageList = try! decoder.decode(PackageList.self, from: Data(contentsOf: fileURL))
		var checkedOutPackages: Set<Remote> = []
		
		while true {
			var enriched = false
			
			for var (packageName, remote) in packageList.packages {
				guard !checkedOutPackages.contains(remote) else {
					continue
				}
				print("\nProcessing package: \(packageName)")
				
				let repositoryName = remote.url.split(separator: "/").last!
				let folderName = repositoryName.replacingOccurrences(of: ".git", with: "")

				let repositorySupposedPath = fileManager.currentDirectoryPath.appending("/\(Self.repositoryBasePath)/\(folderName)")
				if !fileManager.fileExists(atPath: repositorySupposedPath) {
					let cloneTask = Process()
					cloneTask.launchPath = "/usr/bin/env"
					cloneTask.arguments = ["git", "clone", remote.url, "\(Self.repositoryBasePath)/\(folderName)"]
					cloneTask.standardOutput = FileHandle.nullDevice
					cloneTask.standardError = FileHandle.nullDevice
					cloneTask.launch()
					cloneTask.waitUntilExit()
				}
				
				let checkoutTask = Process()
				checkoutTask.launchPath = "/usr/bin/env"
				checkoutTask.arguments = ["git", "checkout", remote.version]
				checkoutTask.currentDirectoryPath = "\(Self.repositoryBasePath)/\(folderName)"
				checkoutTask.standardOutput = FileHandle.nullDevice
				checkoutTask.standardError = FileHandle.nullDevice
				checkoutTask.launch()
				checkoutTask.waitUntilExit()
				if checkoutTask.terminationStatus == 0 {
					print("Tag: \(remote.version)")
				} else {
					print("❗️Could not checkout \(packageName), tag \(remote.version). Check version tag and try again.")
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
					continue
				}
				
				let packagePins = try decoder.decode(Pins.self, from: pinsSerialized)
				let dependencies = extractDependencies(from: packagePins)
				if !dependencies.isEmpty {
					enriched = true
					for dependency in dependencies {
						let package = Remote(url: dependency.url, version: dependency.version)
						packageList.packages[dependency.name] = package
					}
				}
			}
			
			if !enriched {
				break
			}
		}
	}
	
}


func extractDependencies(from packageResolved: Pins) -> [Dependency] {
	packageResolved.pins.map {
		// rethink approach, we have revisions in pins, which are more secure // 🟡
		Dependency(name: $0.identity, url: $0.location, version: $0.state.version)
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
