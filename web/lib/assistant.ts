import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({ maxRetries: 3 });

// Answers a user's question about a template breakdown.
export async function askAssistant(question: string, breakdown: string): Promise<string> {
  const message = await client.messages.create({
    model: "claude-sonnet-5-5",
    max_tokens: 2048,
    system: "You explain how a video edit was made and which editor tools reproduce it.",
    messages: [{ role: "user", content: `${breakdown}\n\nQuestion: ${question}` }],
  });
  const block = message.content[0];
  return block.type === "text" ? block.text : "";
}
