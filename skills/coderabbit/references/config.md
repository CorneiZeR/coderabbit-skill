# `.coderabbit.yaml`

Lives at the repository root. CodeRabbit resolves it from the pull request's **base** branch, so a
change to it only takes effect once merged into the branch the PR targets.

Schema hint for editors:

```yaml
# yaml-language-server: $schema=https://coderabbit.ai/integrations/schema.v2.json
```

Validate it before pushing, with the CLI:

```bash
coderabbit config validate .coderabbit.yaml   # exit 0 valid; 1 missing, malformed, or schema unreachable
```

A file that does not parse is not an error anyone reports back: the review simply runs without the
instructions in it, and reads as a reviewer that has stopped caring about this repository.

A local review can also be given instructions this file does not carry:

```bash
coderabbit review -c CLAUDE.md      # extra instructions, on top of .coderabbit.yaml
```

Useful for trying an instruction before it lands in the repository — but remember that the pull
request pass will not have it, so a finding it produces is one the PR review may never make.

## The settings that decide whether a review happens at all

```yaml
reviews:
  auto_review:
    enabled: true
    drafts: false
    base_branches:
      - 'feat/.*'
      - 'release/.*'
```

`base_branches` is a list of **regexes matched against the base branch name**, and the repository's
default branch is always included. Anything else — a release branch collecting a stack, or a PR
stacked on another feature branch — is reviewed only if it matches, and is otherwise skipped with:

> Review skipped: reviews are disabled for this base branch

Two things worth doing when you touch this list:

- Add the pattern **before** opening the stack, not after the first PR is skipped.
- Delete entries naming a finished release. Dead configuration reads as a supported path, and the
  next person has to work out whether it still matters.

`auto_review.enabled: false` stops the review-per-push behaviour, which is the single biggest
consumer of a limited plan's allowance. With it off, ask for a review when the PR is ready and spend
one slot per PR instead of one per push.

## Tuning what the review says

```yaml
reviews:
  profile: chill          # or 'assertive' — how much it flags
  request_changes_workflow: false
  high_level_summary: true
  review_status: true

  path_filters:
    - '!**/__pycache__/**'
    - '!dist/**'

  path_instructions:
    - path: 'src/**'
      instructions: >-
        What this code has to get right, in your words. Keep it about the traps
        a reviewer cannot infer from the diff — import-time side effects, thread
        boundaries, a serialization format that must round-trip. End with what to
        skip: "no style nits, ruff and mypy already enforce those."
    - path: 'tests/**'
      instructions: >-
        Check that a test would actually fail if the behaviour it covers
        regressed. Flag assertions that hold regardless of the code under test.
```

`path_instructions` is where this file earns its place. Generic instructions produce generic
reviews; naming the specific failure modes of *this* codebase is what turns it into a reviewer that
finds real defects. The `tests/**` instruction above is worth copying verbatim — "would this test
fail if the change were reverted" is the question that catches the most.

```yaml
chat:
  auto_reply: true
```

## Commands, for reference

Posted as pull request comments:

| command | effect |
| --- | --- |
| `@coderabbitai review` | incremental review of commits since the last one |
| `@coderabbitai full review` | re-review the whole PR from scratch |
| `@coderabbitai pause` / `resume` | stop and restart automatic reviews on this PR |
| `@coderabbitai resolve` | resolve all of its review comments |
| `@coderabbitai configuration` | show the configuration in effect |
| `@coderabbitai rate limit` | remaining capacity — costs no review |
| `@coderabbitai help` | the authoritative command list |

When in doubt about a command, ask it with `help` rather than guessing — the set changes.

The local CLI reads this same file, `path_instructions` included, so an instruction is worth
testing with `cr-local.sh` before it is pushed. Note the asymmetry: a pull request resolves
`.coderabbit.yaml` from its **base** branch, a local review from the working tree.
