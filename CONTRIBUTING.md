# Contributing to api-client

Thanks for your interest in contributing. This guide covers the workflow
and conventions used in this project.

## License

By submitting a contribution you agree that your work is licensed under
the [Apache-2.0 License](LICENSE). All contributions are subject to the
same license terms.

## Code of Conduct

All participants are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Started

### Prerequisites

- Ruby 3.2 or newer (CI tests 3.2, 3.3, 3.4, and 4.0)
- Bundler (version managed via `Gemfile.lock`)

### Setup

```sh
git clone https://github.com/belt/api-client.git
cd api-client
bundle install
git config core.hooksPath .githooks
```

The last command enables the pre-push hook that runs the same checks as CI.

### Running Tests

```sh
bundle exec rspec
```

### Linting

```sh
bundle exec standardrb --no-fix   # check only
bundle exec standardrb            # auto-fix
```

### Code Quality

```sh
bundle exec rake quality   # rubycritic, reek, flay, flog
```

## Making Changes

1. Fork the repository and create a branch from `main`.
2. Make your changes in small, focused commits.
3. Add or update tests for any new behavior.
4. Ensure `bundle exec rspec` and `bundle exec standardrb --no-fix` pass.
5. Push your branch and open a pull request against `main`.

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) style:

```text
feat: add retry backoff to streaming adapter
fix: correct timeout handling in async adapter
docs: update JWT onboarding guide
chore(deps): bump faraday to 2.12
test: add property-based tests for URI policy
```

### Pull Requests

- Fill out the [PR template](.github/pull_request_template.md).
- Link related issues with `Closes #123`.
- Keep PRs focused on a single concern.
- CI must pass before merge.

## Reporting Bugs

Use the [Bug Report](https://github.com/belt/api-client/issues/new?template=bug_report.yml)
issue template. Include Ruby version, gem version, and a minimal reproduction.

## Requesting Features

Use the [Feature Request](https://github.com/belt/api-client/issues/new?template=feature_request.yml)
issue template. Describe the use case and expected behavior.

## Security Vulnerabilities

See [SECURITY.md](SECURITY.md) for reporting instructions.

## Development Tips

### Optional Dependencies

The gem auto-detects concurrency adapters. Install optional gems to
test specific adapters:

| Gem | Adapter |
|-----|---------|
| `typhoeus` + `faraday-typhoeus` | Typhoeus (HTTP/2) |
| `async` + `async-http` | Async (fiber-based) |
| `concurrent-ruby` | Concurrent (thread pool) |
| `jwt` | JWT authentication |

### Architecture

See [doc/architecture.md](doc/architecture.md) for system diagrams and
component responsibilities. The [doc/onboarding.md](doc/onboarding.md)
guide walks through the main subsystems.

### Examples

16 canonical clients live in `lib/api_client/examples/`. Each has a
matching spec. Run all with:

```sh
bundle exec rake examples:metrics
```
