import ZivletShelfCore

/// The box's accessibility text (19c §6) as a value: one list, its label and value, one row per item, the bar's
/// buttons, and what to announce. The views read it; the tests check it.
struct BoxAccessibility {
    let listLabel: String
    let value: String
    let rows: [String]
    let buttons: [String]
    let announcement: String?

    init(_ model: BoxViewModel) {
        listLabel = BoxSpeech.header(count: model.items.count, bytes: model.totalBytes)
        let parts =
            (model.selection.isEmpty ? [] : [BoxSpeech.selection(model.selection.count, of: model.items.count)])
            + (model.missingCount > 0 ? [BoxSpeech.missing(model.missingCount)] : [])
        value = parts.joined(separator: ". ")
        rows = model.items.map(\.spoken)
        buttons = model.items.isEmpty ? [] : BoxPress.bar.map(BoxCopy.title)
        if case .dropTarget(let count) = model.presentation.overlay {
            announcement = BoxSpeech.dropTarget(count)
        } else {
            announcement = nil
        }
    }
}
