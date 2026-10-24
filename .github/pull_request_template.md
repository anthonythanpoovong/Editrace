<!-- Delete any section that doesn't apply. -->

## 🎯 Summary

<!-- What does this PR do, and why? Link the issue so it closes on merge: "Closes #123". -->

Closes #



## 📋 What changed

-



## 🧪 How to test

<!-- Steps a reviewer can follow, or the tests that cover this. Paste test output, or eval results for detector and assistant changes (/golden-eval, /rag-eval). -->

1.



## 📈 Coverage

<!-- Changed lines need 80% coverage. If this PR is under, say why and ask a /.github/ code owner for a /coverage-exempt review (see CONTRIBUTING.md). Write "n/a" for docs-only or SQL-only changes. -->



## ⚠️ Risks

<!-- Breaking changes (schema, MCP contracts, migrations), cost impact, rollback plan. Write "None" if none. -->



## 📸 Screenshots

<!-- UI changes only: before and after. -->



## ✅ Checklist

- [ ] CI is green
- [ ] Tests added or updated for new or risky logic
- [ ] `make codegen` run and committed, if the schema changed
- [ ] New tables have RLS policies and a two-user access test
- [ ] No secrets or copyrighted audio committed
- [ ] Docs updated, if behaviour or setup changed
- [ ] Learned something worth keeping (spike result, gotcha, failed approach)? Add a note in `docs/learnings/`
- [ ] Large change (new service, schema or MCP contract change, new setup steps, CI changes, new skills)? Run `/sync-docs` after merge
