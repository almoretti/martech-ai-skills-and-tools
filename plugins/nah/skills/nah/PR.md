# Opening a PR into our repos (NAH 🍌)

Two rules for whoever packages the branch, whatever the repo. A project's own PR rules add to these, never replace them.

1. **Only the tests the repo needs.** Tests written to get the work done (probes, debugging aids, assertions on
   class names or styling, duplicates of a test that already covers the behaviour) stay out of the push. What goes in:
   the tests that fail when the behaviour or the bug fix is broken, and the contract tests the repo already keeps.
2. **A description a reviewer can read in a minute.** The format is the `create-pr` skill in the same marketplace
   (`martech-ai`): open the PR with it and fill its template. Keep only what a reviewer needs: nothing the
   diff already shows, nothing about how you got there.
3. **The last line of every PR body is the NAH footer**, in italics, the banana as the logo:
   `*This PR was not made with TLH, it was made using 🍌 [NAH](https://github.com/almoretti/martech-ai-skills-and-tools/tree/main/plugins/nah).*`
