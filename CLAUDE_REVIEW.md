# Claude Fable 5 — Final Review: Window Hints

**Verdict: APPROVED for submission** (final gate, after GPT-5.6 Sol PASS at round 8 — clean, no warnings)

Pipeline: Grok implemented → GPT-5.6 Sol gated (8 rounds — the most contested of the field) → Claude final review.

## What I verified independently
- **Cold-start race fixed (the r6/r7 judge-fatal bug):** `beginHint` is gated on `clientsReady && monitorsReady`; a summon before Hyprland discovery completes rebuilds once the model is ready, so the judge's very first Super+F always shows hints.
- **Service exclusively owns input/lifecycle:** in both submap and missing-submap fallback modes, overlay keys are forwarded to the keep-loaded service (never `shell call <id>`, which could recurse); the service owns actions, watchdog, and teardown — no orphaned `hinting=true` state.
- **Fixed prefix-free alphabet:** `asdfghjkl` home-row, which excludes the reserved `x` close-prefix and the workspace digits — the r3–r5 configurable-alphabet collision/capacity/race class is gone by construction.
- **Submap-primary input:** compositor-grabbed chords via a managed Hyprland submap (guaranteed capture), overlay is display-only — the correct model the spec mandated.
- **Tests:** 38/38 pass off-device (label allocator determinism/prefix-freedom, coordinate transform, prefix matching, session snapshot).

## Note
This was the hardest-won pass (8 rounds) — the configurable-alphabet feature was correctly cut to a fixed alphabet to eliminate three whole blocker classes, and the input-ownership model took several rounds to get exactly right. The result is simpler and more robust than the original spec.

Two keystrokes to any visible window, zero config, zero daemons. Approved.
