// Node/Bun-only rendering tests. No browser or FiveM bridge is simulated.
Object.assign(globalThis, { window: { fetch: globalThis.fetch } });
