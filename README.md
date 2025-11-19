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

By default repositories are cloned next to your project inside a branch-specific folder named `./.packages-<branch-name>` (for example `./.packages-main`). The `<branch-name>` segment is sanitized (`feature/my-task` becomes `feature__my-task`). Pass a custom second argument if you need to override that path.

```bash
swift run xcgen fetch debug_xcodegen_project_spec.json \
  --dependency-graph-output ./.packages-main/dependency-graph.dot
```

## Commands (man-page style)

### `xcgen fetch`

```
USAGE: xcgen fetch <json-file-path> [<repository-base-path>] [--dependency-graph-output <path>]
```

- Reads your manifest JSON and recursively clones all SwiftPM dependencies.
- Default base path is `./.packages-<branch>`, where `feature/my-task` becomes `./.packages-feature__my-task` (`Sources/xcgen/GitHelpers.swift` holds the sanitizer and the main/master exception).
- The optional `--dependency-graph-output` defaults to `<base>/dependency-graph.dot`.

### `xcgen install-hooks`

```
USAGE: xcgen install-hooks [--force]
```

- Ensures `.packages-main` exists, points `.packages` → `.packages-main`, and appends vendor dirs to `.gitignore`.
- Writes/updates `.git/hooks/post-checkout`, invoking `xcgen worktree post-checkout` (with fallbacks to `.build/{debug,release}/xcgen`).
- Run this from your canonical branch (usually `main` or `master`). Use `--force` to overwrite an existing hook.

### `xcgen worktree add`

```
USAGE: xcgen worktree add <destination-path> <new-branch> [--from <branch-or-commit>] [--skip-dependencies-copy]
```

- Wraps `git worktree add --no-checkout` to spin up a new worktree checked out at `<new-branch>`.
- Copies the source branch’s `.packages-<branch>` folder (or `.packages-main` if missing) into the new worktree as `.packages-<new-branch>` before the first checkout.
- Example: `xcgen worktree add ../repo-feature feature/my-task --from develop`.

### `xcgen worktree post-checkout`

```
USAGE: xcgen worktree post-checkout [<args from git>...]
```

- Invoked by the Git hook after every checkout/switch.
- Detects the current branch and the directory currently pointed to by `.packages` (the branch you just left).
- If checking out `main`/`master`, it simply re-links `.packages` → `.packages-main`.
- Otherwise it creates `.packages-<sanitized-branch>` by copying the directory from the branch you were previously on (falling back to `.packages-main` only if no prior directory exists), then moves the `.packages` symlink to the new branch directory.
- Example:

```
$ git switch feature/my-task
🔗 Linked .packages to .packages-feature__my-task
```


## Contributions

Contributions are welcome! If you would like to help improve this project, please feel free to submit a pull request.
