import { defineConfig } from "vitest/config";

// Coverage feeds the changed-line gate in CI (#129): `npm run test:coverage` writes coverage/lcov.info.
// `include` lists every source file, not only the ones a test imports, so a new file nobody tests shows as 0%.
export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      reporter: ["lcovonly", "text-summary"],
      include: ["app/**", "lib/**", "components/**"],
      // Generated from schema/template.schema.json (#2), tests, type declarations and Next's own files.
      exclude: ["**/*.test.*", "**/*.d.ts", "lib/generated/**", "app/**/layout.tsx"],
    },
  },
});
