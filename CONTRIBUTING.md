# Contributing

Thank you for helping. Zivlet is pre-alpha, so open an issue before you start on a large change. That way we can agree
on the approach first.

## Rules

| Rule | Detail |
|---|---|
| Sign-off (DCO) | Every commit carries a `Signed-off-by: Your Name <you@example.com>` line, which certifies the [Developer Certificate of Origin](https://developercertificate.org). Use `git commit -s`. There is no CLA, and you keep your copyright. Your contribution is licensed GPL-3.0-or-later. |
| Commit format | Conventional commits: `<type>(<scope>): <description>`, where the type is one of `feat fix refactor docs test chore perf ci`. Example: `fix(media): stop the stall watchdog after cancel`. |
| TDD | Write the failing Swift Testing test first, watch it fail, then implement. `make coverage` must pass: every gated module stays at or above 80 % line coverage. |
| Style | Run `make format`, then `make lint`. Keep files to about 400 lines (800 at most) and functions under 50 lines. Prefer immutable value types. |
| Privacy | No telemetry, analytics or network calls. Never log paths, error descriptions that may contain paths, or file contents with `privacy: .public` (`make lint` catches the common cases). |
| Clean room | Don't use code, assets, sounds, icons, UI strings or screenshots from the reference app named in `README.md`, and don't copy code from Open-Tangerine. Describe behaviour in your own words. |

## Before you open a pull request

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make lint test coverage app
```

All four must exit 0. Fill in the pull request template, including the DCO checkbox.

## No CI yet

There is no hosted CI yet: GitHub's hosted macOS runners don't ship Xcode 27, which Zivlet needs. Until a runner that
has it is available, reviewers run the commands above locally. Please paste their summary output into your pull
request.

## Third-party code

If a change adds or updates a dependency, add it to `THIRD_PARTY_NOTICES.md` with its version and licence. The licence
must be compatible with GPL-3.0-or-later. Non-free components (for example fdk-aac, unRAR or any
`--enable-nonfree` ffmpeg build) are not accepted.
