Setup Nim Actions - Simplified (no PhD required)

There is [nimbase/setup-nim-action](https://github.com/nimbase/setup-nim-action) that will help you set up Nim in your GH Actions workflow using a reusable workflow. It simplifies the process of setting up Nim + Your Project in your CI/CD pipeline. Example usage

#### Install nim
```yaml
steps:
  - uses: actions/checkout@v4
  - uses: nimbase/setup-nim-action@main
    with:
      nim-version: '2.2.10'   # 'stable', exact ('1.6.20'), or multiple: [2.2.10, 1.6.20]
  - run: nimble install -y --depsOnly
  - run: nimble build -y
```


#### Test a package
The `test.yml` workflow replaces a 30+ line matrix workflow by a single line that uses the `nimbase/setup-nim-action` workflow. It will automatically install Nim, Nimble, and run your tests. Additionally, custom inputs can be passed to the workflow to customize the behavior of the test run.  [./github/workflows/test.yml](https://github.com/nimbase/setup-nim-action/blob/main/.github/workflows/test.yml)
```yaml
name: test
on: [push, pull_request]
jobs:
  test:
    uses: nimbase/setup-nim-action/.github/workflows/test.yml@main
```

#### Generate and Deploy docs
Build and deploy your Nim docs to Github Pages. You will need to (newbie friendly instructions):
- create a repo named `username.github.io`, add a `_config.yml` file with `theme: jekyll-theme-minimal` content, ([example repo](https://github.com/nimbase/nimbase.github.io/tree/main))
- add the workflow to your nim package repo. The workflow will automatically create a `gh-pages` branch and deploy your docs to it. [./github/workflows/docs.yml](https://github.com/nimbase/setup-nim-action/blob/main/.github/workflows/docs.yml)
- deploy docs, you will need to go to your repo `Settings` > `Pages` > `Build and deployment` (must be set `Deploy from a branch`), and select the `gh-pages` branch and `/ (root)` folder. Save the settings and your docs will be deployed to `https://username.github.io/package-name/`
```yaml
name: docs
on:
  push:
    tags: ['*.*.*']
    # branches:
    #   - main                # deploy docs from main branch
  # workflow_dispatch:        # enable manual trigger to deploy docs from any branch
jobs:
  docs:
    permissions:
      contents: write
    uses: nimbase/setup-nim-action/.github/workflows/docs.yml@main
    with:
      nim-version: stable
      # optional inputs to customize the docs build
```


#### Release binaries
Replaces a 90+ line workflow with a super simple and customizable workflow that builds and release binaries. When `workflow_dispatch` (manual trigger) is enabled, you can specify extra inputs to customize the release with input fields in the UI [./github/workflows/release.yml](https://github.com/nimbase/setup-nim-action/blob/main/.github/workflows/release.yml), otherwise pass inputs to the reusable workflow in your own workflow file to customize the release.

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
      # optional inputs to customize the release
```


Produced binaries will be in the following structure:
```
booyaka_macos-x86_64/
├── LICENSE
├── README.md
└── booyaka

booyaka_linux-x86_64
├── LICENSE
├── README.md
└── booyaka

```