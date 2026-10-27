# QA checklist: Copy Text

Owner rows for Copy Text (P2-103, P2-104) from [18](../18-implementation-plan-m6.md) §7 and
[18d](../18d-m6-ocr-copy-text.md). The recogniser, the text assembly, the clipboard and file writing, the card model
and the setting are covered by unit tests; the 12 rendered fixtures by `make ocr-check` (Z6); the drop path by
`make copy-text-demo` (Z7); the card, Show All and the setting row on screen by `make text-states` (Z9). These rows
check what only a person, real files or another macOS can show.

## Setup

- A build of Zivlet: `make app` (Debug), onboarding finished, the worker present in the bundle.
- At the top of the run, record the macOS build, the Mac model and the Zivlet commit.
- Use files you made yourself, in your own words. Real scans and photos (CT8) stay private and are never committed.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). No result is written until it is
  seen. A fail opens an issue.

## T. Text from images and PDFs

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| CT1 | One image, Hindi and English (Z7 by hand) | Drag an image with a Hindi line and an English line; drop on COPY TEXT | The clipboard holds both lines as written; the card shows the first lines, the character count and "Hindi and English" | |
| CT2 | Save as a text file | Repeat CT1 holding ⌥ at the drop | `<name> Text.txt` appears beside the image; TextEdit opens it as UTF-8 with LF line ends and no BOM | |
| CT3 | Several images | Drop three images; then again with ⌥ | One text with a `— name —` line before each file's text; with ⌥, three `.txt` files | |
| CT4 | A blank image | Drop an image with no text | "No text found"; nothing on the clipboard changes; no file is written | |
| CT5 | PDFs | Drop an English PDF with a text layer; then a Hindi PDF made in Word and one made in Chrome (OS-M6-3) | The English layer's text exactly; the Hindi PDFs read by OCR in the right order, checked by the owner | |
| CT6 | Copying not allowed | Drop a PDF whose permissions forbid copying | "This PDF doesn't allow copying its text."; nothing copied | |
| CT7 | The first run | On a fresh install (or after an OS update), finish onboarding and Copy Text at once | "Preparing text recognition (one time)…", then the text; write down how long it took | |
| CT8 | Real Hindi photos and scans (OS-M6-4) | Receipts, signs, forms; private | Text read and judged by the owner; a CER only where a ground truth was typed | |
| CT9 | Protected folders (OS-M6-5) | Copy Text on files in Desktop, Documents and Downloads with the worker on | No permission prompt, or one that names Zivlet (not the worker) | |

## A. Look and access

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| CT10 | VoiceOver (OS-M6-8) | With VoiceOver on, run CT1; move through the card; open Show All | The card's buttons are announced as "Copy again", "Save as text" and "Show all text"; Show All's text reads line by line | |
| CT11 | Reduce Transparency, Increase Contrast | Turn each on in System Settings › Accessibility › Display; run CT1 and open Show All | The card and Show All use a solid finish; text stays at 4.5:1 or more | |
| CT12 | The setting | Settings › General › Text recognition › Read text in: try each choice, Copy Text after each | Each choice changes the next result's languages; on a Mac without Hindi the Hindi choice is disabled and "Hindi isn't available on this version of macOS." shows below | |
| CT13 | macOS 26.x (OS-M6-2) | On a Mac or VM with macOS 26.x, run `make ocr-check` | Hindi is listed; 12/12 fixtures within 1 % CER; write down the cold compile time | |
