# QA checklist: PDF lock and unlock

Owner rows for LOCK · UNLOCK (P2-106, P2-107) and the S-PDF-LOCK matrix (P2-192) from
[20](../20-implementation-plan-m7.md) §7 and [20f](../20f-m7-pdf-lock.md). Lock, unlock, change, wrong passwords,
legacy inputs and forms are covered by unit tests through qpdf and PDFKit and in the real worker by `make pdf-smoke`
(V6); the drop path of the Debug app by `make lock-demo` (V8). These rows check what only other apps, other
devices and a person's own files can show.

## Setup

- A build of Zivlet: `make app` (Debug) or a Developer ID Release.
- At the top of the run, record the macOS build, the Mac model, each reader's version and the Zivlet commit.
- Use PDFs you made yourself; keep the owner's own form PDFs (PL3) private and never commit them.
- ASCII passwords for PL1's main column; one Devanagari password for its last column.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). No result is written until it is
  seen. A fail opens an issue.

## L. Lock, unlock and other readers

| # | Check | Steps | Expected | Result | Status |
|---|---|---|---|---|---|
| PL1 | S-PDF-LOCK matrix (OS-M7-5) | Lock one PDF with an ASCII password and one with a Devanagari password; open both in Preview, Acrobat Reader, Chrome and Edge on Mac and on Windows, in iOS Files and in one Android reader | The ASCII file opens everywhere with its password and nowhere without it; for the Devanagari file each reader's result is written down (Preview is known not to open it) | | open |
| PL2 | Restrictions honoured | Lock with printing off, copying off and editing off; open in Preview and Acrobat Reader with the user password; try to print, copy text and edit | Each reader refuses what was turned off, or says it is restricted; the owner password, shown once, removes them in Acrobat | | open |
| PL3 | A form stays live | Lock one of your own form PDFs, then unlock the result; fill a field in Preview after each step | The fields are still fields after Lock (once opened) and after Unlock; what was typed before Lock is still there | | open |
| PL4 | Undo of lock and unlock | Lock a PDF and press Undo on the card; unlock a locked PDF and press Undo | Each new file goes to the Trash; the file that was dropped is unchanged and still opens as before | | open |
| PL5 | A locked PDF dropped on a conversion (P2-107) | Not testable in M7: no engine takes a PDF source until P2-12 (PDF → JPG, PNG, TXT, MD). Run it with P2-12: drop a locked PDF on PDF → PNG | The Open sheet asks for its password, then the pages convert | | blocked by P2-12 |
