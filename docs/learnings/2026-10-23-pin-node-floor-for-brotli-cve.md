# Pin a Node patch floor: `node-version: 24` doesn't guarantee a patched 24.x

- **Date:** 2026-10-23
- **Author:** Anthony Thanpoovong
- **Tags:** security, ci, node, vercel
- **Related:** commit ab58bd6 (branch `security/patch-next-and-node`), Brotli CVE-2026-111497

## Context

Patching the Next.js advisories (GHSA-2464-fhr4-w9xw and GHSA-673q-mjm6-r5xr are RCEs, GHSA-p3m5-59mp-jv5r is a Server Actions DoS) and the Node Brotli CVE-2026-111497. The Next.js fix was a dependency bump (16.3.8 to 16.4.3). The Node fix is in the runtime, so a bump in `package.json` doesn't cover it.

## What we tried and found

- Our workflows use `actions/setup-node` with `node-version: 24`. That resolves to a 24.x release, but it can serve a cached older 24.x on the runner, which may still be vulnerable.
- Vercel does not build here: `web/vercel.json` sets `git.deploymentEnabled: false`, and `vercel build` runs in GitHub Actions on the `setup-node` Node. Vercel only executes the prebuilt Functions.
- Per Vercel's docs, `engines.node` overrides the Project Settings Node version, but only at major-version granularity (it picks the latest release Vercel supports within that major). Vercel's docs don't say it enforces a patch floor, so which 24.x patch the Functions runtime runs is unverified. Check a deployment's runtime rather than assuming `>=24.22.1` is enforced.

## What to do next time

- Set `engines.node` to a patch floor and an upper bound (we use `>=24.22.1 <25`). It guards local and CI installs and selects the Vercel major; it is not proof the Functions runtime is patched.
- Add `check-latest: true` to every `setup-node` step (`ci.yml` and the three in `deploy.yml`) so CI resolves the newest matching version.
- When a Node CVE lands, raise the floor in `engines.node`. Run `npm audit` for the dependency side; it doesn't see runtime CVEs.
