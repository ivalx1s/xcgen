# Xcodegen Helper

A helper utility that makes life easier with Xcodegen and SPM-powered Xcode development.

💡Rationale:

Swift Packages are a great way to manage dependencies in Xcode projects, but using them in Xcode can be challenging. Xcode supports proxying Swift Packages with their local copies, which is officially recommended by Apple [Developing a Swift package in tandem with an app](https://developer.apple.com/documentation/xcode/developing-a-swift-package-in-tandem-with-an-app).  However, this setup can become cumbersome as it requires manual management of local packages, including checking out the corresponding version tags. 

The goal of this script is to simplify the process of managing an Xcodegen-powered development environment. It fetches project dependencies (recursively), clones them to a local directory, and checks out the corresponding version tag. 

🚧 Work In Progress

Please note that this project is a work in progress. The code is in a messy state. There are still many features to be added, such as injecting paths to local packages into the project spec to proxy remote packages.

✴️Todo:

- Inject paths to fetched local packages in project spec to proxy remote packages.
- Support YAML-based project spec

---

🔧 Usage

This helper utility is intended to be used when all dependencies are managed through the Swift Package Manager.

```bash
swift run xcgen submodules debug_xcodegen_project_spec.json
```


## Contributions

Contributions are welcome! If you would like to help improve this project, please feel free to submit a pull request.
