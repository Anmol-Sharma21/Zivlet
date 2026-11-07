# QA checklist: Read QR

Owner rows for READ QR (P2-51) from [20](../20-implementation-plan-m7.md) §7 and [20b](../20b-m7-tool-window.md).
Reading codes from images and PDF pages, the payload kinds, the safe Open rule and the results model are covered by
unit tests and `make ocr-check`; the drop path of the Debug app by `make qr-demo` (V9); the results window on screen
by `make tool-states` (V11). These rows check what a camera, a printer and a person's click show.

## Setup

- A build of Zivlet: `make app` (Debug), onboarding finished, the worker present in the bundle.
- At the top of the run, record the macOS build, the Mac model and the Zivlet commit.
- Make the codes yourself (a generator you trust, your own text and links); never commit the photos.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). No result is written until it is
  seen. A fail opens an issue.

## Q. Codes

| # | Check | Steps | Expected | Result | Status |
|---|---|---|---|---|---|
| QR1 | A photographed code | Print a QR code of your own link; photograph it with the Mac's camera app; save the photo and drop it on READ QR | The results window shows the link in full with Copy and Open; Copy copies exactly that link | | open |
| QR2 | A menu PDF with a link | Make a one-page PDF with a QR code of a web link; drop it on READ QR; look at the row; press Open | The row shows the full URL and the page; nothing opens until Open is pressed; Open opens that URL in the default browser | | open |
| QR3 | A code that is not a web link | Drop an image whose QR code holds plain text, and one whose code holds a Wi-Fi setup string (`WIFI:…`) | Each payload shows in full with Copy and no Open; the Wi-Fi row says "Not a web link" | | open |
