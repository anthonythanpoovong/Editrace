import { NextResponse } from "next/server";
import { supabaseAdmin } from "../../../../lib/supabase-admin";

// GET /api/templates/:id returns one template for the breakdown page.
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { data, error } = await supabaseAdmin
    .from("templates")
    .select("*")
    .eq("id", id)
    .single();

  if (error || !data) {
    return NextResponse.json({ error: "Template not found" }, { status: 404 });
  }
  return NextResponse.json(data);
}
