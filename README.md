# Xcodegen Helper

A helper utility that makes life easier with Xcodegen and SPM-powered Xcode development.

💡Rationale:

Swift Packages are a great way to manage dependencies in Xcode projects, but using them in Xcode can be challenging. Xcode supports proxying Swift Packages with their local copies, which is officially recommended by Apple [Developing a Swift package in tandem with an app](https://developer.apple.com/documentation/xcode/developing-a-swift-package-in-tandem-with-an-app).  However, this setup can become cumbersome as it requires manual management of local packages, including checking out the corresponding version tags. 

The goal of this script is to simplify the process of managing an Xcodegen-powered development environment. It fetches project dependencies (recursively), clones them to a local directory, and checks out the corresponding version tag. 

🚧 Work In Progress

Please note that this project is still evolving, but it already manages much more than simply invoking XcodeGen:

- Recursively fetches SwiftPM dependencies and checks out their exact tags via `xcgen fetch`, updating the manifest with local overrides so you can work against your cloned packages.
- Keeps per-branch checkouts in sync when using Git worktrees by copying `.packages-<branch>` folders and relinking `.packages` through `xcgen worktree add`, `xcgen worktree post-checkout`, and the hook installed by `xcgen install-hooks`.
- Provides cleanup helpers such as `xcgen clean all|dd|spm|xc` to remove DerivedData, SwiftPM, and XcodeGen caches when things get messy.

---

🔨 Installing from a local checkout

Build a release binary and place it on your `PATH`:

- Apple Silicon Homebrew prefix: `swift build -c release && sudo install -m 755 .build/release/xcgen /opt/homebrew/bin/xcgen`
- Intel/older Homebrew prefix: `swift build -c release && sudo install -m 755 .build/release/xcgen /usr/local/bin/xcgen`
- Overwrite a Mint-installed binary: `swift build -c release && install -m 755 .build/release/xcgen ~/.mint/bin/xcgen` (no sudo needed)
- If you prefer a personal bin dir: `swift build -c release && install -m 755 .build/release/xcgen ~/bin/xcgen` (ensure `~/bin` is on `PATH`)

After installing, double-check you are picking up the expected binary: `which -a xcgen`. If an older Mint copy still precedes it, adjust `PATH` or remove the old binary.

---

🔧 Usage

This helper utility is intended to be used when all dependencies are managed through the Swift Package Manager.

### Generate a project (default command)

Running `xcgen` without a subcommand proxies to XcodeGen:

```bash
xcgen project.yml
# or from the SwiftPM checkout
swift run xcgen project.yml
```

`xcgen` locates `project.yml` (or any custom spec you pass) and executes `xcodegen --spec <path>` inside that directory. Make sure the [XcodeGen](https://github.com/yonaskolb/XcodeGen) CLI is installed and accessible on your `PATH`.

> ℹ️ Subcommands (`fetch`, `worktree`, etc.) are mutually exclusive with the manifest argument. When you want to run a subcommand, omit the manifest path entirely (e.g. `xcgen fetch ...`).

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
- After a successful fetch it writes `local-<package>` entries (e.g. `local-swift-algorithms`) back to the manifest pointing at `.packages/<package>/` for every resolved dependency, skipping ones that already exist.

### `xcgen clean`

```
USAGE: xcgen clean <target>
```

- `all` – Removes DerivedData, SwiftPM’s caches/configuration, Xcode’s cache directory, and the XcodeGen cache at `~/.xcodegen/cache`.
- `dd` – Removes `~/Library/Developer/Xcode/DerivedData` only.
- `spm` – Removes SwiftPM caches (`~/Library/org.swift.swiftpm` and `~/Library/Caches/org.swift.swiftpm`).
- `xc` – Removes DerivedData plus `~/Library/Caches/com.apple.dt.Xcode`.
- Example: `xcgen clean dd` or `xcgen clean all` when you need a full reset.

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
