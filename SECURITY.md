# Security policy

## What this repository is

Markdown instructions and a handful of shell scripts that call `gh`, `git` and
the `coderabbit` CLI on a developer's own machine. There is no server, no
service and no user data. The realistic risks are therefore local:

- a script running a command it should not, on the repository you are standing
  in;
- a script leaking a token into output, a log file or a comment body;
- an injection through a value that arrives from an API response — a branch
  name, a comment body, a pull request title — and reaches a shell.

Those are worth reporting. So is anything that makes the tooling act as the
wrong account, since the whole point of `cr_ensure_account` is that a write is
published under a name.

## Reporting

**Do not open a public issue for a security problem.** Use GitHub's private
reporting for this repository — *Security* → *Report a vulnerability* — or email
**kolosyuk1@gmail.com**.

Include the version you are on (the commit SHA, since this repository is not
released), what you ran, and what happened. A proof of concept helps; a working
exploit against somebody else's repository is not needed and not wanted.

Expect an acknowledgement within a week. There is one maintainer, so a fix may
take longer than the acknowledgement.

## Supported versions

`main` only. There are no releases and no branches to backport to: pull the
latest commit.

## Verifying what you install

`SHA256SUMS.txt` lists the checksum of every file a user installs. After
cloning:

```shell
shasum -a 256 -c SHA256SUMS.txt
```

It covers the skill's own files and excludes itself and `.github/`. It is a
consistency check on a clone, not a signature — it proves the files match the
manifest in the same commit, and nothing about who wrote that commit.

## Credentials

Nothing here stores a credential. The scripts read whatever `gh` is already
logged in as, and pin themselves to one account for the duration of a run via
`GH_TOKEN` in their own process. If you find a path where a token reaches a
file, a comment or a log line, that is a report.
