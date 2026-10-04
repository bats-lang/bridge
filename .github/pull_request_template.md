## What and why

<!-- What changes, and the issue or spec it answers. -->

Kind: <!-- one of: bug fix / new capability / process, documentation or CI. The review confirms it from the diff. -->

## Bug fix

<!-- Delete this section unless Kind is "bug fix". -->

- The spec it deviates from (the atom's or opcode's documentation, or the platform API it wraps), and how:
- Why this is the minimal fix:
- That it adds or widens no atom or opcode, and puts no policy in bridge:

## New capability (an atom or an opcode)

<!-- Delete this section unless Kind is "new capability". Answer each with evidence: code, measurements, the platform API's documentation. -->

1. Is there no way to do this with what exists, at reasonable performance?
2. Is this the minimal wrapper? Does it map 1:1 to the platform API? Why can it not be broken into smaller atoms? (Always answer; in detail when it is not 1:1.)
3. Does it write to the DOM? If so, is it an opcode of the diff stream (a separate call is an extra JS crossing outside the batch's order)?
4. The plausible alternatives, and why each would not work:
5. Where the app's policy (which attributes, roles, defaults, when) lives: it must be in the app's Bats, not in bridge's JS (bats-lang/pwa#49).

## Review

No merge before an adversarial review (CLAUDE.md, "Adversarial review before merge"): a new comment in this conversation by a trusted author (OWNER, MEMBER or COLLABORATOR), written by another agent or person than the one that wrote the change: all agents post from one account, so reviews are done by a separate reviewer agent, named on a `Reviewer:` line. Its first line is exactly `## Adversarial review`; it has exactly one line `Verdict: approved` or `Verdict: changes needed` and exactly one line `Reviewed: <full head SHA>`, both exact, as written and as GitHub shows them; it is plain text and inline code only (no code fences, no HTML, no link or footnote definitions, ASCII letters). The newest review attempt alone sets the `adversarial-review` status: success only for an unedited, perfectly formed approval of the current head, while no "Request changes" review stands (it stands until dismissed). A formal review can only block: its text counts as a review attempt, and as the newest it makes the status pending. A push after approval needs a new review.
