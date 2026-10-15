# Verification plan

Done means every supported insertion or transfer path refuses an overlapping or out-of-bounds rectangle and an overweight final inventory. Rejected operations retain their prior counts, metadata, money and stock. Accepted moves conserve counts and weight across participants. Default 1x1 definitions preserve old slot behavior. Saved records survive load, reconciliation, save and reload. NUI geometry agrees with the server for the shared fixtures, includes same-anchor rotation and restores rejected moves.

The workflow is high rigor because it touches persistent possessions and economic operations.

1. Trace server, storage and UI independently. Compare whole data-model alternatives before choosing the contract.
2. Capture the unchanged build, native Lua parse results and actual server behavior. Build the verification harness before production changes.
3. Implement the pure grid domain and deterministic recovery. Verify boundaries, overlap, rotation, batch placement and save round trips.
4. Integrate every server mutation and export. Verify transactions through actual registered handlers and exports with explicit runtime stubs.
5. Integrate client transport and NUI rendering, previews, rotation and rollback. Run geometry and reducer tests, TypeScript and production build.
6. Review invariant coverage and new comments independently. Resolve demonstrated defects, rerun affected checks, and document remaining runtime gaps.
7. Commit only task changes on the current branch. Push only origin and create the PR in FjamZoo/ox_inventory with base main.

The throughput checkpoint puts the geometry and transport contract before runtime/UI implementation. Server and UI writers own disjoint files. The harness writer owns tests and the reproducible runtime build helper. One writer owns all authoritative inventory mutation paths because they share state and transaction rules. No worker runs git commands. The lead owns integration, review and publication.

Local evidence is not a live FiveM acceptance run. No server is configured. The browser tool returned no browsers. Live NUI pointer interaction, multiplayer networking, framework persistence and actual game item use remain unverified unless a runtime becomes available during the run.
