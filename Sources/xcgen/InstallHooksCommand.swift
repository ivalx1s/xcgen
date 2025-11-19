import Foundation
import ArgumentParser

struct InstallHooks: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-hooks",
        abstract: "Install the git post-checkout hook and bootstrap the vendor directory layout."
    )

    @Flag(name: .shortAndLong, help: "Overwrite an existing post-checkout hook if present.")
    var force = false

    func run() throws {
        let repoRoot = try Git.repositoryRoot()
        let layout = PackagesLayout(root: repoRoot)
        try layout.ensurePrimaryDirectoryExists()
        try layout.pointSymlink(to: layout.mainDirectory)
        try ensureGitIgnoreEntries(at: repoRoot)

        let gitDirectory = try Git.gitDirectory()
        let hookURL = gitDirectory
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("post-checkout")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: hookURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: hookURL.path), !force {
            throw ValidationError("A post-checkout hook already exists. Rerun with --force to overwrite it.")
        }
        try hookScript().write(to: hookURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o755))
        ], ofItemAtPath: hookURL.path)
        print("✅ Installed post-checkout hook at \(hookURL.path)")
    }

    private func ensureGitIgnoreEntries(at repoRoot: URL) throws {
        let entries = [".packages", ".packages-*", ".packages-main"]
        let gitignoreURL = repoRoot.appendingPathComponent(".gitignore")
        let fileManager = FileManager.default
        var existingEntries: Set<String> = []
        var contents = ""
        if let data = fileManager.contents(atPath: gitignoreURL.path),
           let string = String(data: data, encoding: .utf8) {
            contents = string
            existingEntries = Set(string
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        let missingEntries = entries.filter { !existingEntries.contains($0) }
        guard !missingEntries.isEmpty else { return }
        var updated = contents
        if !updated.isEmpty, !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        updated.append(missingEntries.joined(separator: "\n"))
        updated.append("\n")
        try updated.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        print("✏️ Updated .gitignore with vendor directory rules.")
    }

    private func hookScript() -> String {
        """
#!/bin/bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
if command -v xcgen >/dev/null 2>&1; then
  xcgen worktree post-checkout "$@"
elif [ -x "$REPO_ROOT/.build/release/xcgen" ]; then
  "$REPO_ROOT/.build/release/xcgen" worktree post-checkout "$@"
elif [ -x "$REPO_ROOT/.build/debug/xcgen" ]; then
  "$REPO_ROOT/.build/debug/xcgen" worktree post-checkout "$@"
else
  echo "xcgen binary not found; skipping worktree hook" >&2
fi
"""
    }
}
