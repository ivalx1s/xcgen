import Foundation

struct ManifestUpdater {
    static func addLocalPackages(to manifestURL: URL,
                                 repositoryNames: Set<String>) {
        guard !repositoryNames.isEmpty else { return }
        guard let data = try? Data(contentsOf: manifestURL) else {
            print("❗️ Unable to read manifest at \(manifestURL.path), skipping local package injection.")
            return
        }
        guard var rootObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            print("❗️ Manifest at \(manifestURL.path) is not a JSON dictionary, skipping local package injection.")
            return
        }
        var packagesDictionary = rootObject["packages"] as? [String: Any] ?? [:]
        var additions = 0
        for name in repositoryNames.sorted() {
            let key = "local-\(name)"
            if packagesDictionary[key] != nil { continue }
            packagesDictionary[key] = ["path": ".packages/\(name)/"]
            additions += 1
        }
        guard additions > 0 else { return }
        rootObject["packages"] = packagesDictionary
        do {
            let updatedData = try JSONSerialization.data(withJSONObject: rootObject,
                                                         options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: manifestURL)
            print("✏️ Added \(additions) local package entries to \(manifestURL.lastPathComponent)")
        } catch {
            print("❗️ Failed to update manifest with local packages: \(error)")
        }
    }
}
