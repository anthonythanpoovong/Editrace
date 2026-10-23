# Pin a Node patch floor: `node-version: 24` doesn't guarantee a patched 24.x

- **Date:** 2026-10-23
- **Author:** Anthony Thanpoovong
- **Tags:** security, ci, node, vercel
- **Related:** commit ab58bd6 (branch `security/patch-next-and-node`), Brotli CVE-2026-111497

## Context

Patching the Next.js RCE advisories (GHSA-2464-fhr4-w9xw, GHSA-673q-mjm6-r5xr, GHSA-p3m5-59mp-jv5r) and the Node Brotli CVE-2026-111497. The Next.js fix was a dependency bump (16.3.8 to 16.4.3). The Node fix is in the runtime, so a bump in `package.json` doesn't cover it.

## What we tried and found

- Our workflows use `actions/setup-node` with `node-version: 24`. That resolves to a 24.x release, but it can serve a cached older 24.x on the runner, which may still be vulnerable.
- Vercel builds use whatever `engines.node` in `web/package.json` allows, so with no floor it can run any 24.x.

## What to do next time

- Set `engines.node` to a patch floor and an upper bound (we use `>=24.22.1 <25`). Vercel honours it.
- Add `check-latest: true` to every `setup-node` step (`ci.yml` and the three in `deploy.yml`) so CI resolves the newest matching version.
- When a Node CVE lands, raise the floor in `engines.node`. Run `npm audit` for the dependency side; it doesn't see runtime CVEs.
