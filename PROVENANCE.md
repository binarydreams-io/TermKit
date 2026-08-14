# Provenance

## TUIkit

- Repository: `https://github.com/phranck/TUIkit`
- Fork base: `9f9aaed5ba332adaa678f07744395b9de812bbf0`
- Role: inherited fork source
- License: MIT

TermKit preserves the upstream notice without claiming ownership of inherited code.
Legacy source trees and compatibility targets were removed after the modern behavior baseline was recorded.

## OpenTUI

- Repository: `https://github.com/anomalyco/opentui`
- Role: directly studied design reference for component styles and interaction ideas
- Included source: none identified
- Studied revision: not recorded
- License verification revision: `1500698af07951ea0c1c67c9ad737fc54382ee20`
- License: MIT

## Image Dependencies

| Package | Version | Commit | Role | License |
| --- | --- | --- | --- | --- |
| swift-png | 4.5.1 | `8a0bcd4df5e4b307c804937776a56dd6ecdf6396` | Direct PNG decoder | Apache-2.0 |
| swift-jpeg | 2.1.0 | `c7aa48486cd8920120dd69cda5de62aeb93e1708` | Direct JPEG decoder | Apache-2.0 |
| h | 1.0.1 | `aa3626829160917d4378330617971977cbd78f5b` | Transitive codec support | Apache-2.0 |

The wrapper validates signatures, dimensions, allocation arithmetic, PNG metadata, JPEG frames, and bounded file reads.
It uses deterministic pixel-to-cell sizing and explicit decoding limits.

## Excluded Build Tool

`dollup` is declared by upstream manifests but is absent from the resolved TermKit graph.
TermKit does not download, build, execute, link, or distribute it at the audited revision.
Its license terms were not found. A future graph change must resolve those terms before release.

## Original Player Assets

TermKitPlayer artwork and capture metadata appear in `Examples/Assets/README.md` and `.github/assets/README.md`.

Historical planning records remain in `Documentation/Plans/`. They preserve old names only as migration evidence.
