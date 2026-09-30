---
name: rag-eval
description: Run and interpret the Editrace template-assistant evaluation (#39) — retrieval recall@5, citation support, tool-mapping accuracy and refusal correctness — comparing a branch against main and applying the regression thresholds. Use when changing assistant prompts, retrieval, chunking, embeddings, the docs corpus or the editor tool ontology, or when asked "did this make the assistant better?".
---

# Assistant (RAG) eval

The assistant ships only if it's measurably right. Wrong tool advice costs an editor more time than no advice (#39).

## 0. Preflight
- The eval harness and golden question set (#39, grown from #30) exist. If not, stop. Point to #39. Don't judge assistant changes on a handful of hand-picked questions.
- Know the **current thresholds** (from #39 or the CI config). If none are set yet, report the numbers and say "no gate yet".

## 1. What changed?
Classify the change, because it tells you which metrics to watch:

| Change | Watch most |
|---|---|
| Prompt / system rules | Refusal correctness, citation support |
| Retrieval, chunking, embeddings, hybrid weights | Recall@5, citation support |
| Docs corpus (new or updated editor docs) | Recall@5 for that editor and version; licensing cleared in #21? |
| Editor tool ontology (#31) | Tool-mapping accuracy |
| Model change | Everything, plus cost and latency |

## 2. Run
Baseline (`main`) vs candidate (the branch), on the **same** question set, model settings and corpus snapshot (unless the corpus is what changed). Collect:
- **Retrieval recall@5,** overall and per editor
- **Citation support:** does the cited chunk actually back the claim?
- **Tool-mapping accuracy** against the ontology
- **Refusal correctness:** out-of-scope questions are declined; in-scope ones aren't
- Per question type: template facts, tool mapping, how-to
- **Cost and latency** per answer (tokens, p50/p95)

## 3. Report

```
### Assistant eval · <candidate sha> vs <baseline sha>
Questions: 100 (Resolve 25 · Premiere 25 · FCP 25 · CapCut 25)

| Metric | Base | Cand | Δ | Threshold | |
|---|---|---|---|---|---|
| Recall@5 | 0.82 | 0.86 | +0.04 | ≥ 0.80 | ✅ |
| Citation support | 0.91 | 0.88 | −0.03 | ≥ 0.90 | ❌ |

Tokens/answer: 2.1k → 2.4k · p95 latency: 3.2s → 3.5s
Top regressions: q_041 (CapCut how-to): now cites the wrong version's doc
```
- ❌ on any threshold **blocks merge** (#39). Say so plainly.
- Show 3–5 concrete regressed questions with the old and new answer snippets, so the cause is visible.
- Post on the PR: `gh pr comment <n> --body-file <report.md>`.

## Rules
- Answers must follow the assistant rules in `docs/plan.md`: cite timestamps and docs, flag low confidence, never present a guess as the exact effect, stay in scope. An answer that breaks these fails, even if it sounds right.
- "Which tools are used" comes from the ontology, deterministically. If the LLM is inventing tool names, that's a bug, not a prompt tweak.
- Never add eval questions that you tuned the change on to the gating set. Keep a held-out split.
