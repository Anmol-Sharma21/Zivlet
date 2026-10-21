## Summary

<!-- What does this change, and why? Link the issue: "Closes #123". -->

## Type

- [ ] feat
- [ ] fix
- [ ] refactor
- [ ] docs
- [ ] test
- [ ] chore / perf / ci

## Test plan

<!-- There is no hosted CI yet (no runner with Xcode 27). Run the following locally and paste the summary. -->

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make lint test coverage app
```

- [ ] I wrote the failing test first, then the implementation.
- [ ] `make lint test coverage app` exits 0, and every gated module is at or above 80 % line coverage.
- [ ] For UI or trigger changes: I tried it in a Debug build with a real Finder drag.

## Checklist

- [ ] **DCO:** every commit has a `Signed-off-by:` line (`git commit -s`), and I have the right to submit this work
      under GPL-3.0-or-later ([Developer Certificate of Origin](https://developercertificate.org)).
- [ ] Commit messages follow `<type>(<scope>): <description>`.
- [ ] Clean room: no code, assets, sounds, icons, UI strings or screenshots from the reference app, and no code from
      Open-Tangerine.
- [ ] New or updated third-party components are listed in `THIRD_PARTY_NOTICES.md` with a GPL-3.0-compatible licence.
- [ ] No telemetry or network calls; paths and file contents are not logged publicly.
