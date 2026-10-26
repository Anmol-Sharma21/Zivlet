# 18b — M6 Stream B: P2-100, the catalog cap and combining rule

Part of [18-implementation-plan-m6](18-implementation-plan-m6.md). Conventions: index §6. Acceptance: 05 row P2-100
and 05b's P2-100 note (TRANSCRIBE counted). Lists: [design/17-feature-roadmap](../design/17-feature-roadmap.md) §8.1
and §8.2; interaction W-1 and W-2 (§8.4). Swift below is specification-grade and was not compiled.

Today every list is short (longest: 9 conversions for PDF and documents, 9 tools for a single video, 6 actions), so
the cap cuts nothing; the point of the stream is that the next tool added to a full list fails a test instead of
silently pushing slices off the wheel. COPY TEXT (D9) is the first tool added under the new rule.

---

## Task B1 — Visibility marks in the catalog

| Field | Value |
|---|---|
| Goal | `ToolVisibility { defaultVisible, extra }`. `ApplicabilityRow.single` and `.multi` become `[ToolEntry]` where `ToolEntry(id, visibility)`; a helper keeps the table readable (`.visible(.shrink)`, `.extra(.imageBackdrop)`). `ToolCatalog.tools(for:)` returns visible tools only; a new `extras(for:)` returns the extras (for custom wheels, App Intents and the CLI later). Every current tool is `defaultVisible` (D-M6-17) |
| Acceptance | every existing `ToolCatalogTests` expectation unchanged; a test catalog with one `extra` entry → `tools(for:)` leaves it out and `extras(for:)` returns it |
| Effort | S |

**Files:** modify `Sources/ZivletCore/Catalog/ToolTable.swift`, `Sources/ZivletCore/Catalog/ToolCatalog.swift`,
`Sources/ZivletCore/Catalog/ToolSpec.swift` (`ToolVisibility`); tests `Tests/ZivletCoreTests/ToolCatalogTests.swift`.
`ToolCatalog` gains an internal `init(registry:specs:applicability:)` so tests can pass their own tables.

```swift
@Test func extrasAreLeftOffTheWheelButStayReachable() {
    let catalog = ToolCatalog(
        registry: .standard, specs: ToolCatalog.specTable,
        applicability: [.init(formats: [.png], single: [.visible(.shrink), .extra(.imageBackdrop)], multi: [])])
    #expect(catalog.tools(for: [.png]) == [.shrink])
    #expect(catalog.extras(for: [.png]) == [.imageBackdrop])
}
```

RED: `type 'ToolCatalog.ApplicabilityRow.Entry' has no member 'visible'`. Commit `feat(catalog): mark each tool
visible by default or extra`.

---

## Task B2 — One cap for every list, and its lint

| Field | Value |
|---|---|
| Goal | `SliceBuilder` applies `maxSlots` (12) to the tools list, the same-family conversion list and the actions list, in catalog order (`prefix(maxSlots)`); the mixed-family conversion rule keeps its "only if ≤ 12" behaviour. A lint suite enumerates every format × {1 item, 2 items} for tools and conversions, and the actions list, and fails with the list's name and count when any **default** list (visible entries plus reserved slots, B4) exceeds 12. It prints one line per list (`png single tools 8/12`) so the exit row Z11 can show the counts |
| Acceptance | a test catalog with 13 visible tools for PNG → the lint's helper reports `png single tools 13 > 12` and the builder shows 12; the standard catalog passes; existing `SliceBuilderTests` stay green |
| Effort | S |

**Files:** modify `Sources/ZivletWheelCore/SliceBuilder.swift`, `Sources/ZivletWheelCore/SliceBuilder+Convert.swift`;
create `Sources/ZivletCore/Catalog/CatalogLists.swift` (pure enumeration of every default list with its name, used
by the lint and by the counts printout), `Tests/ZivletCoreTests/CatalogCapLintTests.swift`; extend
`Tests/ZivletWheelCoreTests/SliceBuilderTests.swift`.

```swift
@Suite("Catalog cap lint (P2-100, FR-27, FR-90)")
struct CatalogCapLintTests {
    @Test func noDefaultListIsLongerThanTwelve() {
        let over = CatalogLists.standard.all.filter { $0.count > WheelLimits.maxSlots }
        #expect(over.isEmpty, "over the cap: \(over.map(\.description))")
    }

    @Test func aThirteenthVisibleToolIsReported() {
        let lists = CatalogLists(tools: .withVisibleTools(13, for: .png), conversions: .standard)
        #expect(lists.all.contains { $0.name == "png single tools" && $0.count == 13 })
    }
}
```

`WheelLimits.maxSlots` (12) moves to `ZivletCore` so the core can lint without depending on `ZivletWheelCore`;
`WheelGeometry.maxSlots` reads it. RED: `cannot find 'CatalogLists' in scope`. Commit `feat(catalog): cap every
wheel list at 12 and lint the defaults`.

---

## Task B3 — The combining rule for mixed families

| Field | Value |
|---|---|
| Goal | `ToolSpec` gains `accepts: Set<FormatID>?` — the formats a tool takes when items of **different families** are mixed (nil = not a combining tool). For a mixed selection, `tools(for:)` returns, in catalog order, the visible tools whose `accepts` covers every item and whose cardinality allows the count. Read QR's hard-coded `qualifiesForQRScan` becomes data (`accepts` = every image format, GIF, PDF). Same-family selections keep today's intersection rule. Future combining tools (COMBINE PDF, REEL; Actions ZIP/LOCK) only add data |
| Acceptance | a table of **30 mixed sets** (image+pdf, image+svg, svg+pdf, gif+pdf, audio+video, video+image, image+document, archive+image, folder+file excluded by the existing rule, 2–5 items, with duplicates), each with its expected list; with today's catalog only READ QR survives where it did before (no visible change), and after D9 COPY TEXT joins it for image/PDF mixes; a test catalog with a fake "combine" tool accepting images, SVG and PDF shows it for image+pdf and not for image+audio |
| Effort | M |

**Files:** modify `Sources/ZivletCore/Catalog/ToolSpec.swift`, `Sources/ZivletCore/Catalog/ToolTable.swift`
(`accepts` for `qrScan`), `Sources/ZivletCore/Catalog/ToolCatalog.swift`; create
`Tests/ZivletCoreTests/CombiningRuleTests.swift` (the 30-row table as `@Test(arguments:)`).

```swift
@Test(arguments: MixedSets.thirty)
func mixedSelectionsShowOnlyToolsThatAcceptEveryItem(_ row: MixedSets.Row) {
    #expect(ToolCatalog.standard.tools(for: row.formats) == row.expected, "\(row.formats)")
}
```

RED: the fake-combine row fails (`[]` instead of `[.fakeCombine]`), since today a mixed selection only checks Read
QR. Commit `feat(catalog): mixed selections show the tools that accept every item`.

---

## Task B4 — Reserved slots counted by the cap

| Field | Value |
|---|---|
| Goal | `CatalogLists.reserved` names slots that later rows will fill and that the cap must already count: TRANSCRIBE in audio single/multi and video single/multi (05b, 17 §7). The builder ignores them (nothing to draw); the lint adds them to each list's count |
| Acceptance | video single counts 9 tools + 1 reserved = 10 ≤ 12; a test that reserves 4 slots for video single fails the lint (13); the count line says `mp4 single tools 10/12 (1 reserved)` |
| Effort | S |

**Files:** modify `Sources/ZivletCore/Catalog/CatalogLists.swift`, `Tests/ZivletCoreTests/CatalogCapLintTests.swift`.

RED: the 4-reserved test passes the lint before the change (reserved slots are not counted). Commit
`feat(catalog): count reserved wheel slots in the cap lint`.

---

## Stream B checks before Stream C

`nice -n 10 make test lint coverage` (ZivletCore and ZivletWheelCore stay ≥ 80 %); `nice -n 10 make app`; the
wheel demo still draws: `make demo MODE=tools` (screen awake only).
