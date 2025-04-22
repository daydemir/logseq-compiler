# Changelog

## [0.1.2] - 2025-04-22
### Changed
- Sibling index assignment is now robust and simplified: handles broken or incomplete left_id chains, assigns indices to all siblings (including orphans), and is easier to maintain/read.

## [0.1.1] - 2025-04-22
### Changed
- Sibling index (`weight`) for Hugo export now starts from 1 instead of 0, ensuring correct ordering in Hugo.
- Sibling order calculation fixed: order now matches visual/logical order in Logseq, consistent with Swift implementation.
- Internal: Improved code clarity and maintainability for sibling index logic.
