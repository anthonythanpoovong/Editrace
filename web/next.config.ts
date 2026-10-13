import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Next generates web/AGENTS.md and web/CLAUDE.md into the working tree on every `next dev`. We don't commit them,
  // so they show up as untracked files for everyone. Turn the generation off; add the files deliberately if we want them.
  agentRules: false,
};

export default nextConfig;
