# git-remote-audit

[View script](../scripts/git-remote-audit)

Find repositories whose remotes disagree, whose local branches have unpublished or missing commits, or whose tags differ. The audit queries live remote refs and reports uncommitted changes separately, so stale tracking branches cannot make an outdated checkout appear synchronized.

Repository refs, objects, index, configuration, and working files are preserved. Any missing history needed for commit counts is fetched into private temporary storage and removed on exit.

The `SYNC` column separates integration-branch synchronization from branch and tag housekeeping: `SYNCED`, `PULL`, `PUSH`, `DIVERGED`, or `UNKNOWN`. Policy scopes can also report `LOCAL`, `PINNED`, or `DIFFERS`. A repository can have synchronized source and still have a `REFS` or `REVIEW` finding. These labels describe differences and do not authorize a mutation.

## Quick start

Check repositories in the current directory. The default report gives each repository one row, with incomplete audits first:

```bash
$ git-remote-audit
STATE   REPOSITORY  SYNC     REMOTES    LOCAL / OTHER REFS
ERROR   ./archive   UNKNOWN  unknown    main not checked; unavailable: origin
REVIEW  ./worker    PUSH     match (2)  main: ahead 1 vs mirror, origin; dirty worktree
REFS    ./website   SYNCED   match (2)  main matches; 3 branch-name gaps
OK      ./library   SYNCED   single     main matches

Summary: 4 repositories, 1 matching, 1 review, 1 refs-only, 1 incomplete
1 remote query failed
REFS = names differ only; shared refs match
Details for one repo: git-remote-audit -v <repository>
```

The directory itself and its immediate child repository roots are checked. Every branch and tag is audited in both output modes. A completed audit with findings exits with status `4`; an incomplete audit exits with `1`.

The scan root is labeled with its directory name, such as `website`, and nested repositories retain paths relative to that root. Summary rows, explanations, and diagnostics use the same labels without expanding every entry into a long absolute path.

## Common examples

**Check a directory of projects:**

```bash
$ git-remote-audit ~/projects
```

**Include repositories inside groups, nested checkouts, and initialized submodules:**

```bash
$ git-remote-audit --recursive ~/projects
```

**Inspect the complete ref inventory for a repository:**

```bash
$ git-remote-audit -v ~/projects/website
```

Verbose output includes every missing or differing ref, object IDs for differing tags and remote refs, and matching refs. Use it on a repository from the summary to decide which differences need action.

**Explain branch housekeeping without matching-tag noise:**

```bash
$ git-remote-audit --explain ~/projects/website
```

Focused explanations identify local-only branches, associated worktrees, remote-only branches, and branches already contained in the integration history. An exact tree match with an integration ancestor is reported separately from ancestry containment, so rewritten commits do not automatically imply unfinished file changes. Dirty or unreadable associated worktrees are explicitly marked for preservation. Cleanup candidates still require review of ignored contents and retention requirements; the audit never deletes them. Other branches are marked for review without assuming whether their changes were rebased, squashed, or superseded.

**Get full details recursively:**

```bash
$ git-remote-audit -rv ~/projects
```

## Reading the summary

| State | Meaning |
|---|---|
| `ERROR` | At least one check was incomplete; the row identifies unavailable remotes or unknown state |
| `REVIEW` | Commit or tag values differ, the checked-out branch is missing on a side, or local state needs review, such as a dirty worktree, detached HEAD, or no remotes |
| `REFS` | Differences are limited to ref names absent from one or more sides; shared ref values match |
| `OK` | All checked refs match and the working tree is clean, when present |

Rows are sorted in that order, then by repository path. Differences can be intentional. Topic branches, backup tags, forks, and separately published histories do not all need the same response; the audit describes the difference without prescribing a push, pull, merge, or deletion.

The `REMOTES` column compares remote branch and tag sets independently of local state: `match (N)`, `differ (N)`, `single`, `unknown`, or `none`. A single remote can still be compared fully with local refs. `unknown` means remote parity could not be established.

`LOCAL / OTHER REFS` leads with the checked-out branch. It explicitly says `main matches` when that branch agrees with all queried remotes, even if other branch or tag names differ. When commits differ, the direction is local: `ahead 2 vs origin` means two local commits are absent from that remote; `behind 3 vs origin` means three remote commits are absent locally. Divergence shows both counts. Matching remotes are grouped, and failed queries remain explicit.

Other differences are summarized by unique ref name within each category: other branch values, tag values, branch-name gaps, and tag-name gaps. The same missing branch is counted once even when several remotes lack it. A ref can have both a missing copy and differing values among its existing copies. Name gaps mean absence on a compared side, not proof that a branch should be pushed or deleted. The checked-out branch is described directly instead of being counted again among other refs.

Dirty working trees include staged, unstaged, and untracked changes. File names and contents are not printed. Bare, detached, and unborn states remain explicit. Detached HEAD is not assigned to an arbitrary remote branch; named local branches are still compared. An unborn HEAD has no branch ref until its first commit.

The footer distinguishes incomplete repositories from failed remote queries. A repository with two unreachable remotes contributes one incomplete repository and two failed queries.

## Reading verbose details

`Remotes: match` means every queried remote advertises the same branch and tag names with the same object IDs. Detail rows compare each reachable remote against the first reachable remote. `Local vs <remote>` compares same-named local and remote refs; upstream mappings do not rename branches for comparison.

| Detail | Meaning |
|---|---|
| `ahead 2, behind 0` | The local branch has two commits absent from the remote branch |
| `ahead 0, behind 3` | The remote branch has three commits absent from the local branch |
| `diverged (ahead 2, behind 3)` | Each branch has commits absent from the other |
| `missing locally` | The remote has a branch or tag with no same-named local ref |
| `missing on remote` | A local branch or tag has no same-named remote ref |
| `tag release: differs` | The tag object IDs differ, even if both tags ultimately point to the same commit |
| `ahead/behind unknown` | The refs differ, but complete ancestry could not be established |

## Read-only behavior and incomplete results

The script uses live `git ls-remote` results rather than cached tracking refs. When branch ancestry is missing locally, an explicit source-only fetch reads the needed branch history into a temporary object directory. Fetch ref mappings, bundle downloads, tag updates, pruning, automatic maintenance, submodule fetch recursion, lazy fetching, fsmonitor hooks, and optional index writes are disabled for the audit. The repository's authentication and transport configuration remain in effect.

A failed remote query or unavailable commit count makes the audit incomplete and returns `1`, even when differences have also been found. Other reachable remotes and repositories are still checked. Shallow clones can establish equal tips and missing refs; differing branch tips have unknown counts because shallow boundaries would make ahead/behind results unreliable.

Diagnostics identify the repository, remote, failed operation, and Git exit status where available. Raw Git transport errors are withheld because they can contain credential-bearing URLs. To investigate a query failure, run `git ls-remote <remote>` inside that repository. For unavailable history, inspect whether the clone is shallow and retry after resolving transport errors or concurrent remote changes.

## Repository expectations

Use `--policy policy.json` to audit a declared integration branch even when a task branch is checked out, map differently named local and remote branches, or describe independent remotes. JSON parsing conditionally requires Python 3; ordinary audits and help do not.

```json
{
  "version": 1,
  "repositories": [
    {
      "path": "/home/projects/website",
      "localBranch": "main",
      "remote": "origin",
      "remoteBranch": "source",
      "mirrors": ["origin", "mirror"],
      "independent": ["upstream"],
      "sourceOnly": true
    }
  ]
}
```

`path` is required and absolute. `remote` defaults to `origin`; omitted branch names use that remote's live default branch. `mirrors` defaults to the selected source remote and compares the selected remote branch on each named mirror. `independent` names intentionally different remotes; they remain queried, and access failures still make the audit incomplete. Their parity and upstream integration are outside this source audit, which does not establish whether a fork needs rebasing onto an independent upstream. Other configured remotes retain ordinary ref comparison and are labeled unclassified rather than silently assumed to mirror the source.

`sourceOnly` excludes generated publication refs and tags and explicitly reports that publication refs were not checked. `localOnly` expects a repository without remotes. `pin` accepts a full commit ID and checks a submodule against its parent's committed gitlink; detached HEAD at that pin is expected. These scoped checks do not certify excluded publication output or submodule remote parity.

Adapters can supply a `problems` array of preflight diagnostics and an informational `note`. A preflight problem makes that repository incomplete before querying its remotes. The adapter must establish repository URL identity; policy itself does not declare or validate remote URLs. Unlisted repositories retain ordinary audit behavior, and absent policy paths do not create an inventory or recovery check.

All fields other than `path` are optional. Booleans default to false, `problems` defaults to an empty array, and `note` defaults to an empty string. Unknown or duplicate keys, duplicate paths, invalid branch names, overlapping remote roles, control characters, and policy files larger than 2 MiB are rejected. Paths with spaces are supported. `mirrors` and `independent` contain unique remote names, and the selected source remote cannot be independent.

---

## Reference

### All options

| Flag | Description |
|---|---|
| `directory` | Directory to scan; defaults to the current directory |
| `-r, --recursive` | Discover repositories at every depth |
| `-v, --verbose` | Show the complete per-ref report, including matching refs |
| `-e, --explain` | Explain differing branches, worktrees, and cleanup candidates |
| `-p, --policy FILE` | Read generic repository expectations from JSON |
| `-h, --help` | Show complete usage and behavior |
| `--` | Treat remaining arguments as positional, including a directory starting with `-` |

Options may be interleaved with the directory, and short flags may be bundled, such as `-rv`.

### Environment variables

| Variable | Description |
|---|---|
| `TMPDIR` | Temporary storage parent; defaults to `/tmp` |
| `NO_COLOR` | Disable help styling, taking precedence over `CLICOLOR_FORCE` |
| `CLICOLOR_FORCE` | Enable help styling even when stdout is redirected |

Inherited Git repository-location variables are cleared so one caller's `GIT_DIR` or `GIT_WORK_TREE` cannot redirect the scan to another repository. Git authentication and transport configuration are honored. HTTP terminal credential prompts are disabled; SSH follows its normal configuration.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Audit completed without findings |
| `1` | Incomplete audit, runtime failure, or interruption |
| `2` | Invalid arguments, inaccessible scan root, or no repositories found |
| `3` | Git missing or lacking required `--no-lazy-fetch` support |
| `4` | Completed with differences, dirty working trees, detached HEAD, or no remotes |

### Dependencies

- Bash 3.2 or newer
- Git with `--no-lazy-fetch` support
- Python 3, only when using `--policy`

### Scope and limitations

Only advertised `refs/heads/*` and `refs/tags/*` are compared. Remote HEAD, server-hidden refs, hosting configuration, permissions, and separate push URLs are outside scope. Each named remote uses its first fetch URL, following Git's fetch behavior. Remotes intentionally containing different branch sets will produce findings.

Recursive scanning does not follow descendant directory symlinks or enter `.git` administration directories or bare repository internals. Normal working trees, linked worktrees, initialized submodules, hidden directories, and bare repositories are supported. An uninitialized submodule is not a local repository and is not audited.

Remote observations happen sequentially. The report is not an atomic snapshot across servers; concurrent remote changes can require a rerun. Temporary disk and network usage depend on the missing branch history. Interrupting the audit removes its temporary storage.
