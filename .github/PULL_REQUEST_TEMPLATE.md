## Summary

<!-- Describe the change, its reason, and its user-visible effect. -->

## Verification

<!-- List the exact commands that you ran and their results. -->

- [ ] I ran focused tests for the changed behavior.
- [ ] I ran the full macOS and Linux gate with `./scripts/test-linux.sh`.
- [ ] I ran `./scripts/swifttui-benchmark.sh` if this changes runtime, rendering, layout, or animation behavior.
- [ ] I used only Swift 6.0.3-compatible APIs and preserved macOS and Linux support.
- [ ] I preserved module dependency direction and used the correct invalidation level.
- [ ] I updated public documentation for behavior or API changes.
- [ ] I updated licenses, notices, credits, or provenance records when required.

## Legacy TUIkit Regression

<!-- If this changes legacy TUIkit evidence, explain why and confirm that it does not expose a public legacy product. -->

- [ ] This change does not treat legacy TUIkit targets, vendors, or API tools as public SwiftTUI products.
