// Armour smoke test: intentionally flawed, do not merge.
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);

export async function getTemplate(templateId: string) {
  const { data } = await supabase.from("templates").select("*").eq("id", templateId).single();
  return data;
}
