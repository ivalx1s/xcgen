XCGEN – Automated Bootstrapping for XcodeGen-based Xcode Workflow
==================================================================

This shell script streamlines the setup and maintenance of Xcode projects that leverage XcodeGen and the Swift Package Manager (SPM). It executes a 
series of tasks, including:

*   **Dependency Verification**: Checks and ensures that critical system dependencies—Homebrew, XcodeGen, and Mint—are installed correctly.
*   **Xcode Project Generation**: Utilizes XcodeGen to generate an Xcode project file from the project specification.
*   **Xcode Project Launch**: Automatically opens the generated Xcode project.

The script uses two subcommands, `bootstrap` and `fetch`, to control its execution.

This script encapsulates critical setup and maintenance tasks for XcodeGen-based Xcode projects with SPM, significantly simplifying the iOS 
development workflow. By automating these tasks, you can focus more on building amazing features and less on the intricacies of project setup.

Usage:
------

- Place this shell script in the project root directory alongside the XcodeGen manifest.
- Fine-tune for your use case, e.g., remove GraphQL or SwiftGen related parts if you don't need them, or add those specific to your project.
- Ensure the script is executable with `chmod +x .xcgen`.
- Add `alias xcgen='./.xcgen'` to your `.zshrc` profile.
- Run `xcgen bootstrap`.
- After pulling new code from the repository, regenerate the Xcode project using the `xcgen` command.

The `bootstrap` subcommand is geared towards preparing the development environment. It installs necessary tools, with a focus on Mint, which is then 
used for installing and managing XcodeGen and other scripts crucial to the project generation pipeline.

In this setup, we utilize the following scripts (should be defined in the Mintfile):

*   **xcodegen**: Generates the Xcode project file from the project specification (in JSON format).
*   **xcgbootstrap**: Fetches Swift packages as defined in the XcodeGen project specification.
*   **apollo-ios-cli**: Generates native Swift types from a GraphQL schema.
*   **swiftgen**: Generates Swift namespaces and values for resources such as colors, fonts, images, and localization strings.

The `fetch` subcommand updates the repositories of dependencies. This command should be used when the XcodeGen project specification is updated with 
new version tags.

The `clean` subcommand can be used to wipe all the Xcode and SPM related caches.

---

Ensure packages are proxied by local paths in your XcodeGen manifest, for example:

packages:
  local-swift-collections:
    path: "../Packages/swift-collections/"
  remote-swift-collections:
    url: https://github.com/apple/swift-collections.git
    version: 1.0.2

The xcgbootstrap script automatically creates the `Packages` folder in the parent directory of your project directory. This setup allows Xcode to accommodate local changes in packages, track these changes in its GUI, and launch much faster. As a result, the overall developer experience is significantly enhanced compared to when remote packages are used.
