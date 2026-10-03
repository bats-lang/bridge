## What and why

<!-- What changes, and the issue or spec it answers. -->

Kind: <!-- one of: bug fix / new capability / process, documentation or CI -->

## Bug fix

<!-- Delete this section unless Kind is "bug fix". -->

- The spec it deviates from (the atom's or opcode's documentation, or the platform API it wraps), and how:
- Why this is the minimal fix:

## New capability (an atom or an opcode)

<!-- Delete this section unless Kind is "new capability". Answer each with evidence: code, measurements, the platform API's documentation. -->

1. Is there no way to do this with what exists, at reasonable performance?
2. Is this the minimal wrapper? Does it map 1:1 to the platform API? If not, why can it not be broken into smaller atoms?
3. Does it write to the DOM? If so, is it an opcode of the diff stream (a separate call is an extra JS crossing outside the batch's order)?
4. The plausible alternatives, and why each would not work:
5. Where the app's policy (which attributes, roles, defaults, when) lives: it must be in the app's Bats, not in bridge's JS (bats-lang/pwa#49).

## Review

No merge before an adversarial review: a comment by someone other than the author, first line `## Adversarial review`, with a line `Verdict: approved` or `Verdict: changes needed` and a line `Reviewed: <full head SHA>` (CLAUDE.md, "Adversarial review before merge"). The `adversarial-review` status follows the newest one, and is success only for an approval that names the current head: a push after approval needs a new review.
