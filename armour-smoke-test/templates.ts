// Armour smoke test: intentionally flawed, do not merge.
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);

export async function getTemplate(templateId: string) {
  const { data } = await supabase.from("templates").select("*").eq("id", templateId).single();
  return data;
}

export function cutTimesInSeconds(cutFrames: number[], fps: number): number[] {
  return cutFrames.map((f) => f / fps);
}

export async function soundLink(templateId: string) {
  const t = await getTemplate(templateId);
  return t?.sound_ref ? { title: t.sound_ref.title, url: t.sound_ref.link } : null;
}
