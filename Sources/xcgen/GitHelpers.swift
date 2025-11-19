import Foundation

enum GitHelperError: LocalizedError {
    case commandFailed(arguments: [String], exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let exitCode):
            return "git \(arguments.joined(separator: " ")) failed with exit code \(exitCode)"
        }
    }
}

enum Git {
    static func run(_ arguments: [String], at directory: URL? = nil) throws -> String {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["git"] + arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.launch()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitHelperError.commandFailed(arguments: arguments, exitCode: process.terminationStatus)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func currentBranch(at directory: URL? = nil) throws -> String {
        try run(["rev-parse", "--abbrev-ref", "HEAD"], at: directory)
    }

    static func repositoryRoot(at directory: URL? = nil) throws -> URL {
        let path = try run(["rev-parse", "--show-toplevel"], at: directory)
        return URL(fileURLWithPath: path)
    }

    static func gitDirectory(at directory: URL? = nil) throws -> URL {
        let path = try run(["rev-parse", "--git-dir"], at: directory)
        return URL(fileURLWithPath: path)
    }
}

enum BranchNaming {
    private static let primaryBranches: Set<String> = ["main", "master"]

    static func sanitized(_ branch: String) -> String {
        var result = ""
        for character in branch {
            if character == "/" {
                result.append("__")
                continue
            }
            if character.isLetter || character.isNumber {
                result.append(character)
                continue
            }
            if ["-", "_", "."].contains(String(character)) {
                result.append(character)
                continue
            }
            result.append("_")
        }
        if result.isEmpty {
            return "HEAD"
        }
        return result
    }

    static func isPrimary(_ branch: String) -> Bool {
        primaryBranches.contains(branch)
    }

    static func packagesDirectoryName(for branch: String) -> String {
        if isPrimary(branch) {
            return ".packages-main"
        }
        return ".packages-\(sanitized(branch))"
    }
}
