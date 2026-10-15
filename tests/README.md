# Native server tests

Run from the resource root with the standalone CfxLua interpreter.

```powershell
$cfxLua = './path/to/cfxlua.exe'
& $cfxLua tests/run.lua
& $cfxLua tests/run.lua --baseline
& $cfxLua tests/run.lua --grid
```

The default suite checks existing 1x1 behavior. `--baseline` records the existing placement and weight defects. `--grid` checks desired footprint rejection and intentionally fails before the grid implementation. All suites exit nonzero on an assertion failure.

`server/fixture.lua` loads the real inventory, shop, crafting, hook, and lock modules. It captures the real registered exports and callbacks. Tests call these interfaces and assert literal slot records, weights, money, stock, and persistence records. Each fixture gets a fresh module cache and real inventory instances.

The boundary fixture supplies item definitions and simplified item metadata policy. It copies metadata, limits non-stack item creation to one item per record, and disables automatic durability expiry. It supplies empty configuration data unless a test provides shop, stash, vehicle, or crafting data.

Database operations use an in-memory payload store. The fake JSON adapter snapshots tables behind opaque string tokens. Save/load tests therefore verify record selection, fields, reconstruction, and weight through real module methods. They do not verify JSON encoding, SQL, framework bridges, or production item metadata generation. Set `loadServer = true` to load root `server.lua` and test its real player reconstruction export. Framework setup and pefcl initialization are stubbed in that mode.

Engine notifications are captured. Threads execute immediately, timers remain queued until `fixture:flushTimeouts()`, and `Wait` fails explicitly. Tests can replace `fixture.await[name]` to exercise callback reentrancy during crafting. Real hooks and locks remain active. Coordinates default to the same position. No test here proves FiveM scheduling, network transport, entity ownership, or client rendering.

## Build the interpreter

```powershell
./tools/build-test-lua.ps1
```

The optional Windows helper discovers MSVC through `vswhere`. Pass `-VcVarsPath` if discovery is unavailable. It downloads pinned official CitizenFX Lua and GLM archives into a new temporary directory and compiles the native CfxLua syntax extensions. It never rewrites resource Lua or removes directories. An optional `-BuildDirectory` must name a directory that does not yet exist. The final output line is the interpreter path.

The pinned sources are [CitizenFX Lua 4b086dc](https://github.com/citizenfx/lua/tree/4b086dc082da96a8e21aaa38ef7c0f4a7697f2a4) and [CitizenFX GLM c1b4c6b](https://github.com/citizenfx/glm/tree/c1b4c6b60135d5c286052b4affaf5b330a057c8c). A stock Lua interpreter cannot parse the resource's compound assignment, optional chaining, or backtick hash syntax.
