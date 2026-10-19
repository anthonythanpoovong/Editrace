import { NextResponse } from "next/server";
import { ZodError } from "zod";
import { readTemplate, UnsupportedVersionError } from "../../../../lib/read-template";

// POST /api/templates/validate checks a template document before the editor saves it. It reads nothing from
// the database, so it needs no session. The response lists the elements this schema version would skip.
const MAX_BYTES = 1_000_000;

export async function POST(req: Request) {
  const text = await req.text();
  if (text.length > MAX_BYTES) {
    return NextResponse.json({ error: "Template is larger than 1 MB" }, { status: 413 });
  }
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return NextResponse.json({ error: "Body must be JSON" }, { status: 400 });
  }
  try {
    const { skipped } = readTemplate(body);
    return NextResponse.json({ valid: true, skipped });
  } catch (error) {
    if (error instanceof UnsupportedVersionError) {
      return NextResponse.json({ valid: false, error: error.message }, { status: 422 });
    }
    if (error instanceof ZodError) {
      return NextResponse.json({ valid: false, issues: error.issues }, { status: 422 });
    }
    throw error;
  }
}
