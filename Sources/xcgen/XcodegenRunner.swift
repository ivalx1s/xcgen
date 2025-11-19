import Foundation

enum XcodegenRunnerError: LocalizedError {
    case specNotFound(String)
    case commandFailed(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .specNotFound(let path):
            return "XcodeGen spec not found at \(path)"
        case .commandFailed(let exitCode):
            return "xcodegen command failed with exit code \(exitCode)"
        }
    }
}

enum XcodegenRunner {
    static func generateProject(specPath: String) throws {
        let fileManager = FileManager.default
        let resolvedURL = URL(fileURLWithPath: specPath,
                              relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath))
            .standardizedFileURL
        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            throw XcodegenRunnerError.specNotFound(resolvedURL.path)
        }

        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["xcodegen", "--spec", resolvedURL.path]
        process.currentDirectoryURL = resolvedURL.deletingLastPathComponent()
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.launch()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XcodegenRunnerError.commandFailed(exitCode: process.terminationStatus)
        }
    }
}
