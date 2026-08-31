# Design QA — Codex task-card identity separation

Date: 2026-08-30
Scope: Expanded-island task-card leading identity only.

## Visual target

Preserve the existing Dev Island task-card typography, density, nine-dot status language, and supplied Codex brand mark while removing the malformed composite appearance shown in the user screenshot.

- Reference: `/var/folders/vn/c2f3lky55r30gyrq4r9r44z40000gn/T/TemporaryItems/NSIRD_screencaptureui_mEerrr/截屏2026-08-29 02.47.53.png`
- Rendered implementation: `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/task-card-logo-separation-v1-20260830/63-real-debug-codex-task-card.jpeg`
- Multi-agent snapshot: `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/task-card-logo-separation-v1-20260830/62-task-card-leading-identity.png`

## Comparison

The reference combined three signals inside one small square: badge background, Codex glyph, and a bottom-trailing status matrix. The live Debug build now uses two non-overlapping slots: the nine-dot state matrix first, followed by a bare Codex glyph. The title and metadata remain aligned to the existing card grid.

## Findings

- P0: none.
- P1: none.
- P2: none.
- P3: the supplied Codex glyph remains a monochrome template asset so it can follow Dev Island's palette. A future switch to an official multicolor asset requires separate redistribution/trademark approval and is outside this layout fix.

## Verification

- Targeted layout and snapshot tests: 2 passed, 0 failed.
- Full source suite from the implementation run: 717 passed, 0 failed.
- Production and Debug app bundles: Universal arm64 + x86_64; strict deep code-signature verification passed.
- Real Debug Sandbox flow: spawned Codex approval, denied the synthetic request, then inspected the restored running task card in the expanded island.
- Production hermetic launch smoke: 8 samples, isolated services, unlocked display, normal AppKit exit status 0.

final result: passed
