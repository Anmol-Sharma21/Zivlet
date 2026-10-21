# Security policy

## Supported versions

Zivlet is pre-alpha and has no releases yet. Security fixes go to the `main` branch. Once releases exist, only the
latest release will get fixes.

## Reporting a vulnerability

**Please don't open a public issue for a security problem.**

Report it privately through GitHub's security advisories: open the repository's **Security** tab, choose
**Report a vulnerability**, and fill in the form. Only the maintainers can see the report.

Useful details:

- the Zivlet commit or version, the macOS version and the Mac model;
- what an attacker can do, and what they need first (for example, a crafted file the user drops on the wheel);
- the steps to reproduce, with a sample file if one is needed. Strip any personal data from the sample.

## What to expect

- We aim to acknowledge a report within 7 days.
- We'll keep you updated while we investigate and fix it, and agree a disclosure date with you.
- You'll be credited in the advisory unless you ask us not to credit you.

## Scope

In scope:

- Zivlet's own code;
- how it runs bundled helpers such as ffmpeg (argument handling, input confinement, entitlements);
- how it handles hostile or malformed input files;
- the update channel, once there is one.

If a vulnerability is in a third-party component (see `THIRD_PARTY_NOTICES.md`), please report it to that project as
well.
