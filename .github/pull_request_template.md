## What and why

<!-- What changes. If it adds or edits a rule, what failure it came from and
what that failure cost. -->

## Checklist

Strike out with `~~...~~` what does not apply, rather than leaving it unticked.

- [ ] A rule added or changed in `SKILL.md` has its provenance in `WHY-IT-EXISTS.md`, ending with a `→` pointer back to the section
- [ ] A rule names what its absence cost, concretely
- [ ] A script change survives a failed read: an empty string, a `null`, a zero count are told apart from an answer
- [ ] No write is retried, and no guard's only effect is its output
- [ ] `shasum -a 256 -c SHA256SUMS.txt` passes, regenerated if an installed file changed
- [ ] Numbers a reader can count were counted, not estimated
