import Foundation
import ArgumentParser

struct Worktree: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: "Manage Git worktrees and branch-specific dependency directories.",
        subcommands: [
            PostCheckout.self,
            Add.self
        ]
    )
}

extension Worktree {

    struct PostCheckout: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "post-checkout",
            abstract: "Sync the .packages symlink for the currently checked-out branch."
        )

        @Argument(help: "Passthrough arguments from git post-checkout.", completion: .none)
        var passthrough: [String] = []

        func run() throws {
            let repoRoot = try Git.repositoryRoot()
            let branch = try Git.currentBranch()
            let layout = PackagesLayout(root: repoRoot)
            try layout.ensurePrimaryDirectoryExists()
            let previousDirectory = layout.currentSymlinkDestination()
            if BranchNaming.isPrimary(branch) {
                try layout.pointSymlink(to: layout.mainDirectory)
                print("🔗 Linked .packages to \(layout.mainDirectory.lastPathComponent)")
                return
            }
            let branchDirectory = layout.directory(for: branch)
            try layout.ensureBranchDirectoryExists(branchDirectory,
                                                   preferredSource: previousDirectory)
            try layout.pointSymlink(to: branchDirectory)
            print("🔗 Linked .packages to \(branchDirectory.lastPathComponent)")
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Create a new worktree with branch-specific dependencies pre-populated."
        )

        @Argument(help: "Destination path for the new worktree.")
        var destinationPath: String

        @Argument(help: "Name of the new branch to create in the worktree.")
        var branchName: String

        @Option(name: .long, help: "Branch or commit to base the new branch on. Defaults to the currently checked out branch.")
        var from: String?

        @Flag(name: .long, help: "Skip copying dependencies from the source worktree.")
        var skipDependenciesCopy = false

        func run() throws {
            let fileManager = FileManager.default
            let destinationURL = URL(fileURLWithPath: destinationPath, relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath)).standardized
            if fileManager.fileExists(atPath: destinationURL.path) {
                throw ValidationError("Destination \(destinationURL.path) already exists.")
            }

            let repoRoot = try Git.repositoryRoot()
            let baseBranch = try from ?? Git.currentBranch()

            try runGitWorktreeAdd(destinationURL: destinationURL,
                                  newBranch: branchName,
                                  baseBranch: baseBranch)
            if !skipDependenciesCopy {
                try copyDependencies(from: repoRoot,
                                     baseBranch: baseBranch,
                                     to: destinationURL,
                                     newBranch: branchName)
            }
            try runGitCheckout(destinationURL: destinationURL, branch: branchName)
            print("✅ Worktree created at \(destinationURL.path)")
        }

        private func runGitWorktreeAdd(destinationURL: URL,
                                       newBranch: String,
                                       baseBranch: String) throws {
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = [
                "git",
                "worktree",
                "add",
                "--no-checkout",
                "-b",
                newBranch,
                destinationURL.path,
                baseBranch
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.launch()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ValidationError("git worktree add failed with exit code \(process.terminationStatus)")
            }
        }

        private func copyDependencies(from repoRoot: URL,
                                      baseBranch: String,
                                      to destinationURL: URL,
                                      newBranch: String) throws {
            let fileManager = FileManager.default
            let sourceLayout = PackagesLayout(root: repoRoot)
            let destinationLayout = PackagesLayout(root: destinationURL)
            let sourceDirectory = sourceLayout.directory(for: baseBranch)
            guard fileManager.fileExists(atPath: sourceDirectory.path) else {
                print("ℹ️  No dependencies to copy from \(sourceDirectory.lastPathComponent).")
                return
            }
            let destinationDirectory = destinationLayout.directory(for: newBranch)
            try destinationLayout.copyDirectory(from: sourceDirectory, to: destinationDirectory)
            print("📦 Copied dependencies to \(destinationDirectory.lastPathComponent)")
        }

        private func runGitCheckout(destinationURL: URL, branch: String) throws {
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = [
                "git",
                "-C",
                destinationURL.path,
                "checkout",
                branch
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.launch()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ValidationError("git checkout \(branch) failed with exit code \(process.terminationStatus)")
            }
        }
    }
}

struct PackagesLayout {
    let root: URL

    var mainDirectory: URL {
        root.appendingPathComponent(".packages-main", isDirectory: true)
    }

    var symlink: URL {
        root.appendingPathComponent(".packages", isDirectory: false)
    }

    func directory(for branch: String) -> URL {
        let name = BranchNaming.packagesDirectoryName(for: branch)
        return root.appendingPathComponent(name, isDirectory: true)
    }

    func ensurePrimaryDirectoryExists() throws {
        try FileManager.default.ensureDirectoryExists(at: mainDirectory)
    }

    func ensureBranchDirectoryExists(_ directory: URL, preferredSource: URL?) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) { return }
        if let preferredSource,
           fileManager.fileExists(atPath: preferredSource.path) {
            try copyContents(from: preferredSource, to: directory)
            return
        }
        if fileManager.fileExists(atPath: mainDirectory.path) {
            try copyContents(from: mainDirectory, to: directory)
            return
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func pointSymlink(to directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: symlink.path) {
            try fileManager.removeItem(at: symlink)
        }
        let relativePath = directory.lastPathComponent
        try fileManager.createSymbolicLink(atPath: symlink.path, withDestinationPath: relativePath)
    }

    func copyDirectory(from source: URL, to destination: URL) throws {
        try copyContents(from: source, to: destination)
    }

    func currentSymlinkDestination() -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: symlink.path) else { return nil }
        do {
            let relativePath = try fileManager.destinationOfSymbolicLink(atPath: symlink.path)
            let absolute = URL(fileURLWithPath: relativePath, relativeTo: root).standardizedFileURL
            return absolute
        } catch {
            return nil
        }
    }

    private func copyContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) { return }
        if !fileManager.fileExists(atPath: source.path) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}

extension FileManager {
    func ensureDirectoryExists(at url: URL) throws {
        if fileExists(atPath: url.path) { return }
        try createDirectory(at: url, withIntermediateDirectories: true)
    }
}
