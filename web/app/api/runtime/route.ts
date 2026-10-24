import { NextResponse } from "next/server";

// Reports the Node version the deployed Functions runtime is running. Vercel's deployment metadata only shows the major
// (24.x), so this is how we check a Node patch actually reached production. Signed-in users only: it is not in the
// proxy's public paths, so a signed-out visitor is sent to /login before reaching it.
export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({ node: process.version });
}
