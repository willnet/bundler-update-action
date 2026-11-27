# Bundler Update Action

Keep the Bundler version in `Gemfile.lock` current while Dependabot handles application gems. The action opens a pull request when a newer compatible stable release is available. Later runs update the same branch and pull request. [Dependabot issue #4095](https://github.com/dependabot/dependabot-core/issues/4095)

## Quick start

Add `.github/workflows/update-bundler.yml`. During development, replace `REVIEWED_COMMIT_SHA` in the examples with the full commit SHA you have reviewed. The workflow runs on Mondays at 00:30 UTC and can also be started manually.

```yaml
name: Update Bundler
on:
  schedule:
    - cron: '30 0 * * 1'
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: willnet/bundler-update-action@REVIEWED_COMMIT_SHA
```

With the default token, enable **Allow GitHub Actions to create and approve pull requests** under **Settings → Actions → General → Workflow permissions**. Organization policy may control this setting.

On GitHub.com, a PR opened, synchronized, or reopened using `GITHUB_TOKEN` can trigger PR workflows, but a user with write access must approve the runs from the PR. Pushes and other PR activity from this token generally do not trigger workflows. Explicit `workflow_dispatch` and `repository_dispatch` events can start runs. Use an App or PAT when CI should start automatically under the repository's usual rules. [GitHub workflow trigger rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

## Authentication alternatives

For either alternative, set the workflow's `permissions` to `contents: read` for checkout. Grant the supplied token **Contents: read and write** and **Pull requests: read and write** on the target repository.

### GitHub App

Install the App on the target repository. After checkout, generate an installation token using the App client ID and private key.

```yaml
- uses: actions/create-github-app-token@v3
  id: app
  with:
    client-id: ${{ vars.APP_CLIENT_ID }}
    private-key: ${{ secrets.APP_PRIVATE_KEY }}
    permission-contents: write
    permission-pull-requests: write
- uses: willnet/bundler-update-action@REVIEWED_COMMIT_SHA
  with:
    token: ${{ steps.app.outputs.token }}
```

### Personal access token

Create a fine-grained PAT scoped to the repository with the permissions above. Store it as the Actions secret `UPDATE_TOKEN`.

```yaml
- uses: willnet/bundler-update-action@REVIEWED_COMMIT_SHA
  with:
    token: ${{ secrets.UPDATE_TOKEN }}
```

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `token` | `github.token` | Token for pushing the branch and managing the PR |
| `ruby-version` | Auto-detect | Ruby override passed to ruby/setup-ruby |
| `bundler-version` | `same-major` | Stay within the locked major, use `latest` to allow major updates, or specify a RubyGems requirement |
| `working-directory` | `.` | Project directory relative to the workflow workspace |
| `branch` | `bundler-update` | Dedicated PR branch. Use a different branch for each independently updated project |
| `labels` | Empty | Existing PR labels separated by commas or newlines |

For example, to allow major releases for a project in a subdirectory:

```yaml
- uses: willnet/bundler-update-action@REVIEWED_COMMIT_SHA
  with:
    working-directory: services/api
    branch: bundler-update-api
    bundler-version: latest
```

If checkout uses `path: repo`, include that prefix in `working-directory` (for example, `repo/services/api`). The lockfile path within the checkout must be free of commas and line breaks because the PR action treats them as path separators.

Use `bundler-version: '~> 2.6'` for releases from 2.6 up to 3.0 (exclusive), or `'~> 2.6.0'` for 2.6.x. Multiple bounds can be comma-separated.

## Outputs

| Output | Meaning |
| --- | --- |
| `updated` | String `true` if the lockfile changed, otherwise `false` |
| `previous-version` | Bundler version at checkout |
| `current-version` | Bundler version after the run |
| `pull-request-number` | Number returned by the PR step, empty when unavailable |
| `pull-request-url` | URL returned by the PR step, empty when unavailable |

## Compatibility and lockfile changes

Ruby setup reads the version configuration (such as `.ruby-version`) in the working directory. Set `ruby-version` explicitly if the project keeps that configuration elsewhere. The setup step skips Bundler installation and dependency caching. [ruby/setup-ruby](https://github.com/ruby/setup-ruby)

The action checks stable releases on RubyGems.org against the running Ruby and RubyGems versions and the requested constraint. If none is newer than the locked version, the run succeeds without opening a PR. If an earlier update PR has become unnecessary, the PR action closes it. It installs the exact target Bundler if needed and invokes that version directly, so the old locked executable need not run.

For Bundler 2.6 and newer, the action uses `bundle lock --update --bundler=VERSION`. Older targets use `bundle update --bundler`, which can install application gems. Bundler may record the runner platform. If any other lockfile section changes, the action restores the original file and fails before creating a PR. [Bundler lock](https://bundler.io/man/bundle-lock.1.html) · [Bundler update](https://bundler.io/man/bundle-update.1.html)

## Troubleshooting

- **Ruby version could not be detected** — If you specify Ruby only in the Gemfile, set the action input explicitly (for example, `ruby-version: '3.4'`). Automatic detection reads `.ruby-version`, `.tool-versions`, or `mise.toml`.
- **Missing Gemfile.lock** — Commit the lockfile with a `BUNDLED WITH` section, check out the base branch, and set `working-directory` to the directory containing both files.
- **No PR** — Check the Ruby and RubyGems requirements of the desired Bundler release and your `bundler-version` policy. Older candidates are skipped.
- **Unexpected lockfile changes** — Run the target Bundler locally and inspect the diff. Resolve dependency, platform-specific gem, or lockfile format changes separately before retrying.
- **Dependency resolution failed** — Ensure private gem sources are accessible in the job and the Gemfile supports the selected Ruby.
- **PR creation denied** — Check token permissions, repository Actions settings, and branch rules. Use a clean checkout and reserve the update branch for this action.

## License

[MIT](LICENSE)
