# Contributing

TermKit requires Swift 6.3.3. Install the repository toolchain before you submit a change.

## Development

1. Create a focused change in the applicable `Sources/TermKit` subsystem.
2. Add tests in the matching `Tests/TermKitTests` directory.
3. Build with warnings as errors.
4. Run the focused tests, then run the full root test suite.
5. Run the example tests when the change affects runtime or presentation behavior.

```bash
swift build -Xswiftc -warnings-as-errors
swift test
swift test --package-path Examples
```

Keep invalidation scopes narrow. Do not add private frame loops or timers when the shared scheduler can express the demand.
Update documentation, snapshots, and provenance when a change affects those artifacts.

Use conventional commit messages. Follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Report vulnerabilities through the process in [SECURITY.md](SECURITY.md), not through a public issue.
