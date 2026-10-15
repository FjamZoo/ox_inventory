# Native server tests

Run from the resource root with the standalone CfxLua interpreter.

```powershell
$cfxLua = './path/to/cfxlua.exe'
& $cfxLua tests/run.lua
& $cfxLua tests/run.lua --compatibility
& $cfxLua tests/run.lua --geometry
```

The default runs every native suite except the historical baseline. Individual selections are `--compatibility`, `--geometry`, `--grid`, `--insertion`, `--moves`, `--economy`, `--recovery`, `--mutations`, `--esx`, `--lifecycle`, and `--weapons`. `--grid` includes every grid integration group. All suites exit nonzero on an assertion failure.

The explicit `--baseline` suite records the old placement and weight defects. It is expected to fail after those defects are fixed and is excluded from the default. The captured pre-change results remain in `baseline-output.txt`.

`server/fixture.lua` loads the real inventory, shop, crafting, hook, and lock modules. It captures the real registered exports and callbacks. Tests call these interfaces and assert literal slot records, weights, money, stock, and persistence records. Each fixture gets a fresh module cache and real inventory instances.

The boundary fixture supplies item definitions and simplified item metadata policy by default. It copies metadata, limits non-stack item creation to one item per record, and disables automatic durability expiry. `realItems = true` loads the real item shared/server/container modules using the fixture definitions. It supplies empty configuration data unless a test provides shop, stash, vehicle, or crafting data. `items` adds definitions to the defaults.

Database operations use an in-memory payload store. The fake JSON adapter snapshots tables behind opaque string tokens. Save/load tests therefore verify record selection, fields, reconstruction, and weight through real module methods. Fake confiscation and restoration transactions honor injected save failures and change ownership only on success. These tests do not verify JSON encoding, SQL transaction behavior, or framework bridges. Set `loadServer = true` to load root `server.lua` and test its real player reconstruction export. Framework setup and pefcl initialization are stubbed in that mode.

The geometry suite reads the same `fixtures/grid.json` used by the NUI tests. The small test-only JSON reader supports unescaped fixture strings and ordinary numbers. It is separate from the fake persistence adapter.

The ESX suite also loads the real MySQL module with a query-capture boundary fixture. It verifies literal transaction statements and parameters for canonical grid storage, confiscation, restoration, bulk saves, empty ownership, and reserved-row cleanup. It does not execute SQL against a database.

The lifecycle suite uses `bridge-fixture.lua` to load the actual ND, QBX and ESX bridge modules with fake framework player lookups. It exercises disconnects and framework synchronization errors during durable operations. It does not start those framework resources.

The weapon suite uses `client-update-fixture.lua` to execute verbatim extracts of the real `updateInventory`, `updateSlots`, `syncInventory` and `swapItems` handlers with mocked game natives. It checks emitted server payloads and client processing order, including equipped-anchor remapping and late responses. It does not run the full client, game animations or network transport.

Engine notifications are captured. Startup threads run after module loading, and their startup delays are skipped. Subsequent threads execute immediately, timers remain queued until `fixture:flushTimeouts()`, and subsequent `Wait` calls fail explicitly. Tests can replace `fixture.await[name]` to exercise callback reentrancy during crafting. Real hooks and locks remain active. Coordinates default to the same position. No test here proves FiveM scheduling, network transport, entity ownership, or client rendering.

## Build the interpreter

```powershell
./tools/build-test-lua.ps1
```

The optional Windows helper discovers MSVC through `vswhere`. Pass `-VcVarsPath` if discovery is unavailable. It downloads pinned official CitizenFX Lua and GLM archives into a new temporary directory and compiles the native CfxLua syntax extensions. It never rewrites resource Lua or removes directories. An optional `-BuildDirectory` must name a directory that does not yet exist. The final output line is the interpreter path.

The pinned sources are [CitizenFX Lua 4b086dc](https://github.com/citizenfx/lua/tree/4b086dc082da96a8e21aaa38ef7c0f4a7697f2a4) and [CitizenFX GLM c1b4c6b](https://github.com/citizenfx/glm/tree/c1b4c6b60135d5c286052b4affaf5b330a057c8c). A stock Lua interpreter cannot parse the resource's compound assignment, optional chaining, or backtick hash syntax.

## NUI checks

```powershell
cd web
bun install --frozen-lockfile
bun test
bun run build
bun run start --host 127.0.0.1
```

With the development server running, use another terminal in `web`.

```powershell
node tests/browser.mjs
```

The browser script runs separately from `bun test`. It checks actual pointer dragging, R rotation preview, accepted authoritative movement, edge rejection, server rejection, Shift splitting, and recovery reclaim against the explicit browser fixtures. It also captures three screenshots and checks browser errors. It does not contact a FiveM server.

`NUI_URL` defaults to `http://localhost:5173/`. `CHROME_PATH` selects a browser executable. On Windows the script tries standard Chrome install paths. Otherwise it uses Playwright's installed Chromium. Install that browser with `bunx playwright-core install chromium` if needed. `SCREENSHOT_DIR` selects the screenshot directory. Omitted output uses a new directory under the system temporary directory, printed when the run passes.
