# nimbase/setup-nim-action

Set up Nim on GitHub Actions and ship it end-to-end: **test**, **document**, and
**release** your Nim packages across platforms with a handful of lines.

The repo bundles four building blocks:

| Block | What it does | Use it for |
| --- | --- | --- |
| [`action.yml`](action.yml) | Composite action: installs Nim (prebuilt → Homebrew → source) and adds it to `PATH` | Any step that needs `nim`/`nimble` |
| [`.github/workflows/test.yml`](.github/workflows/test.yml) | Reusable workflow: run your package's tests on an OS matrix | CI for Nim packages |
| [`.github/workflows/docs.yml`](.github/workflows/docs.yml) | Reusable workflow: generate `nim doc` HTML and deploy to GitHub Pages | Documentation hosting |
| [`.github/workflows/release.yml`](.github/workflows/release.yml) | Reusable workflow: build binaries per OS/arch, package them and create a GitHub release | Cross-platform releases |

## Usage

### 1. Just install Nim (any job)

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nimbase/setup-nim-action@main
    with:
      nim-version: '2.2.10'   # 'stable', exact ('1.6.20'), or range ('2.x')
  - run: nimble install -y --depsOnly
  - run: nimble build -y
```

### 2. Test a package (replaces a 30+ line matrix workflow)

```yaml
name: test
on: [push, pull_request]
jobs:
  test:
    uses: nimbase/setup-nim-action/.github/workflows/test.yml@main
```

Customize anything:

```yaml
jobs:
  test:
    uses: nimbase/setup-nim-action/.github/workflows/test.yml@main
    with:
      nim-version: '2.2.10'
      os: '[{"os":"ubuntu-latest"},{"os":"windows-latest"}]'
      test-command: nimble test
      pre-test-command: nimble install https://github.com/openpeeps/smuggler
```

> Tip: to test multiple Nim versions, use a caller-side matrix:
> ```yaml
> strategy:
>   matrix:
>     nim: [2.2.10, 1.6.20]
> jobs:
>   test:
>     uses: nimbase/setup-nim-action/.github/workflows/test.yml@main
>     with:
>       nim-version: ${{ matrix.nim }}
> ```

### 3. Generate and deploy docs (replaces a 40+ line workflow)

```yaml
name: docs
on:
  push:
    tags: ['*.*.*']
jobs:
  docs:
    permissions:
      contents: write
    uses: nimbase/setup-nim-action/.github/workflows/docs.yml@main
    with:
      nim-version: stable
```

The docs workflow runs `nim doc --index:on --project --path:. --out:.gh-pages <src>`,
renames the module page to `index.html` (with the two `sed` fixes), and pushes to
the `gh-pages` branch. Point your Pages source at `gh-pages`.

### 4. Release binaries (replaces a 90+ line workflow)

```yaml
name: release
on:
  push:
    tags: ['*.*.*']
jobs:
  release:
    permissions:
      contents: write
    uses: nimbase/setup-nim-action/.github/workflows/release.yml@main
    with:
      nim-version: '2.2.10'
      app-name: myapp
```

This builds `myapp` on the default matrix
(`ubuntu-latest/x86_64`, `macos-14/arm64`, `macos-15-intel/x86_64`,
`windows-latest/x86_64`), packages each into
`myapp_<os>-<arch>.tar.gz` (Windows: `.zip`), and creates a GitHub release with
all archives attached.

To trigger a manual release without pushing a tag, add `workflow_dispatch` and
pass `release-tag: v1.2.3`.

## Inputs (`action.yml`)

| Input | Default | Description |
| --- | --- | --- |
| `nim-version` | `stable` | `stable`, exact version (`2.2.10`), or range (`2.x`, `1.6.x`) |
| `nim-install-directory` | `.nim_runtime` | Directory (workspace-relative) to install into |
| `repo-token` | *(empty)* | Accepted for compatibility; not required |

### Outputs (`action.yml`)

| Output | Description |
| --- | --- |
| `nim-version` | Resolved exact version that was installed |
| `nim-version-full` | Full first line of `nim --version` |
| `nimble-version` | Full first line of `nimble --version` |
| `nim-install-directory` | Absolute path to the installed Nim directory |
| `nim-path` | Absolute path to `nim` |
| `nimble-path` | Absolute path to `nimble` |

## Inputs (`test.yml`)

| Input | Default | Description |
| --- | --- | --- |
| `nim-version` | `stable` | Nim version to test against |
| `os` | `[{"os":"ubuntu-latest"},{"os":"windows-latest"},{"os":"macos-15"}]` | JSON array of `{os}` objects |
| `install-command` | `nimble install -Y` | Installs dependencies (empty to skip). Override to use another tool (e.g. `clue install`) |
| `pre-test-command` | *(empty)* | Command run before the test command |
| `test-command` | `nimble test` | Command that runs the tests. Override to use another tool (e.g. `clue test`) |
| `cache` | `true` | Cache `~/.nimble` between runs |

## Inputs (`docs.yml`)

| Input | Default | Description |
| --- | --- | --- |
| `nim-version` | `stable` | Nim version used for `nim doc` |
| `nim-src` | *(auto)* | Main module; defaults to `src/<repo>.nim` |
| `deploy-dir` | `.gh-pages` | Output dir for the generated HTML |
| `deps-command` | `nimble install -Y` | Installs dependencies |
| `doc-command` | *(auto)* | Full doc command override |
| `deploy` | `true` | Push docs to `publish-branch` |
| `publish-branch` | `gh-pages` | Branch docs are deployed to |

## Inputs (`release.yml`)

| Input | Default | Description |
| --- | --- | --- |
| `app-name` | *(required)* | Binary name |
| `nim-version` | `stable` | Nim version to build with |
| `nim-install-directory` | `.nim_runtime` | Nim install directory (cache + setup) |
| `target-matrix` | 4-runner set (see above) | JSON array of `{os, arch}` |
| `checkout` | `true` | Check out the repository |
| `cache` | `true` | Cache `~/.nimble` + Nim install |
| `install-command` | `nimble install -y --depsOnly` | Dependency install command. Override to use another tool (e.g. `clue install`) |
| `build-command` | `nimble build -y` | Build command. Override to use another tool (e.g. `clue build --release`) |
| `test-command` | *(empty)* | Optional test command before packaging |
| `bin-directory` | `bin` | Directory (relative to workspace) holding the built binary |
| `binary` | *(auto)* | Path to the built binary (`<bin-directory>/<app-name>`, `.exe` on Windows) |
| `extra-files` | `LICENSE README.md` | Extra files copied into the archive |
| `archive-type` | `auto` | `auto`, `tar.gz`, `zip`, or `both` |
| `archive-name` | *(auto)* | Archive base name (`<app-name>_<os>-<arch>`) |
| `create-release` | `true` | Create the GitHub release |
| `release-tag` | *(empty)* | Tag for manual (`workflow_dispatch`) releases |
| `release-title` | *(tag)* | Release title |
| `release-notes` | *(empty)* | Release notes (single line; prefer the file input) |
| `release-notes-file` | *(empty)* | Path to a release notes file |
| `prerelease` | `false` | Mark as pre-release |
| `draft` | `false` | Create as draft |

### Outputs (`release.yml`)

| Output | Description |
| --- | --- |
| `release-url` | URL of the created release |
| `nim-version` | Resolved Nim version used for the build |

## How Nim is installed

| Platform | Strategy |
| --- | --- |
| Linux x86_64 | Prebuilt `tar.xz` from `nim-lang.org` |
| Linux arm64 | Build from source (`./build_all.sh`) |
| macOS | Prebuilt `tar.xz` (published for the newest 2 releases) → Homebrew (exact match only) → source build |
| Windows x86_64 | Prebuilt `.zip` from `nim-lang.org`, extracted with PowerShell |

`stable` is resolved from `nim-lang.org/channels/stable`; version ranges are
resolved with `git ls-remote --tags` + `sort -V` (no `jq`, no API rate limits).
Nightlies and `devel` are intentionally **not** supported.

> **macOS notes**: prebuilt binaries for older versions are no longer published,
> so old versions fall back to Homebrew (only if it matches the exact version)
> or a source build (~10–20 min). On ARM macOS runners, an x86_64 prebuilt runs
> under Rosetta 2. Nightlies/devel are unsupported by design.

## Notes

- The release workflow installs Homebrew `openssl@3` on macOS arm64 runners and
  adds it to `LIBRARY_PATH`/`CPATH`. macOS no longer ships a linkable system
  `libssl` on arm64, so packages using `std/ssl`/OpenSSL would otherwise fail to
  link with `ld: library 'ssl' not found`.
- Reusable workflows reference the action with the `$/` self-repository syntax,
  so they always run the exact commit they were pinned to.
- The docs and release workflows write to the repo (`gh-pages` / a release), so
  callers must grant `permissions: contents: write` on the calling job.

## Development

`.github/workflows/ci.yml` self-tests the action: `stable` on four runners,
version-range resolution, and the Linux arm64 source-build fallback (the slow
macOS source-build path runs on `workflow_dispatch` only).

## License

MIT. Derived in part from [jiro4989/setup-nim-action](https://github.com/jiro4989/setup-nim-action).
