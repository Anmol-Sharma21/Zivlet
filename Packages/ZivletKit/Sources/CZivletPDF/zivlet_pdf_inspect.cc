// zv_pdf_inspect and zv_pdf_check (plan 20d C4, 20e D1). Inspect gives the facts of qpdf's --json and the check walks
// the document as its --check does, but neither prints anything or shows the encryption (either would print a
// recovered user password, D-M7-16).
#include "zivlet_pdf_private.hh"

#include <qpdf/Pl_Discard.hh>
#include <qpdf/QPDFAcroFormDocumentHelper.hh>
#include <qpdf/QPDFEmbeddedFileDocumentHelper.hh>
#include <qpdf/QPDFExc.hh>
#include <qpdf/QPDFFormFieldObjectHelper.hh>
#include <qpdf/QPDFObjectHandle.hh>
#include <qpdf/QPDFOutlineDocumentHelper.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFPageLabelDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>

#include <algorithm>
#include <cstdio>
#include <limits>
#include <string>
#include <vector>

using zivlet_pdf::guarded;
using zivlet_pdf::open_document;
using zivlet_pdf::Secret;

namespace {

/// qpdf names no cipher before V 4 (everything is RC4 there), and none for an /Identity crypt filter after it.
zv_pdf_method method_of(QPDF::encryption_method_e method, int version) {
    switch (method) {
    case QPDF::e_none:
        return version < 4 ? ZV_PDF_METHOD_RC4 : ZV_PDF_METHOD_IDENTITY;
    case QPDF::e_rc4:
        return ZV_PDF_METHOD_RC4;
    case QPDF::e_aes:
        return ZV_PDF_METHOD_AES128;
    case QPDF::e_aesv3:
        return ZV_PDF_METHOD_AES256;
    default:
        return ZV_PDF_METHOD_UNKNOWN;
    }
}

uint32_t clamped(size_t value) {
    return value > std::numeric_limits<uint32_t>::max() ? std::numeric_limits<uint32_t>::max()
                                                        : static_cast<uint32_t>(value);
}

/// The /P bit (counted from 1, as the PDF specification does) as a mask.
constexpr uint32_t p_bit(int bit) { return uint32_t{1} << (bit - 1); }

/// What the file grants, each bit read by qpdf under the file's own revision.
uint32_t allowed_bits(QPDF &pdf) {
    return (pdf.allowPrintLowRes() ? p_bit(3) : 0) | (pdf.allowModifyOther() ? p_bit(4) : 0) |
           (pdf.allowExtractAll() ? p_bit(5) : 0) | (pdf.allowModifyAnnotation() ? p_bit(6) : 0) |
           (pdf.allowModifyForm() ? p_bit(9) : 0) | (pdf.allowAccessibility() ? p_bit(10) : 0) |
           (pdf.allowModifyAssembly() ? p_bit(11) : 0) | (pdf.allowPrintHighRes() ? p_bit(12) : 0);
}

constexpr uint32_t all_allowed =
    p_bit(3) | p_bit(4) | p_bit(5) | p_bit(6) | p_bit(9) | p_bit(10) | p_bit(11) | p_bit(12);

/// The header's version and the warnings so far. getVersionAsPDFVersion reads the catalog, which a refused open has
/// no key for; the header's text needs none. The field widths keep a hostile header from overflowing an int.
void describe_header(QPDF &pdf, zv_pdf_info &info) {
    int major = 0, minor = 0;
    (void)std::sscanf(pdf.getPDFVersion().c_str(), "%4d.%4d", &major, &minor);
    info.pdf_major = major;
    info.pdf_minor = minor;
    info.warning_count = clamped(pdf.numWarnings());
}

/// What the encryption dictionary says; all of it is readable without the password.
void describe_encryption(QPDF &pdf, zv_pdf_info &info) {
    int revision = 0, permissions = 0, version = 0;
    QPDF::encryption_method_e streams = QPDF::e_none, strings = QPDF::e_none, files = QPDF::e_none;
    if (!pdf.isEncrypted(revision, permissions, version, streams, strings, files)) {
        info.handler = ZV_PDF_HANDLER_NONE;
        info.allowed = all_allowed;
        info.streams = info.strings = info.files = ZV_PDF_METHOD_NONE;
        return;
    }
    info.handler = ZV_PDF_HANDLER_STANDARD;
    info.revision = revision;
    info.version = version;
    info.allowed = allowed_bits(pdf);
    info.streams = method_of(streams, version);
    info.strings = method_of(strings, version);
    info.files = method_of(files, version);
}

/// The page dictionaries' annotations, with `subtype` only.
bool any_annotation(std::vector<QPDFPageObjectHelper> &pages, std::string const &subtype) {
    return std::any_of(pages.begin(), pages.end(),
                       [&](QPDFPageObjectHelper &page) { return !page.getAnnotations(subtype).empty(); });
}

bool has_attachments(QPDF &pdf, std::vector<QPDFPageObjectHelper> &pages) {
    return QPDFEmbeddedFileDocumentHelper(pdf).hasEmbeddedFiles() || any_annotation(pages, "/FileAttachment");
}

bool has_javascript(QPDFObjectHandle root, std::vector<QPDFPageObjectHelper> &pages) {
    QPDFObjectHandle const names = root.getKey("/Names");
    if (names.isDictionary() && names.hasKey("/JavaScript")) {
        return true;
    }
    QPDFObjectHandle const opening = root.getKey("/OpenAction");
    if (opening.isDictionary() && opening.getKey("/S").isNameAndEquals("/JavaScript")) {
        return true;
    }
    return root.hasKey("/AA") || std::any_of(pages.begin(), pages.end(), [](QPDFPageObjectHelper &page) {
               return page.getObjectHandle().hasKey("/AA");
           });
}

bool is_signature(QPDFFormFieldObjectHelper &field) { return field.getFieldType() == "/Sig"; }

void describe_acroform(QPDFAcroFormDocumentHelper &forms, zv_pdf_info &info) {
    auto fields = forms.getFormFields();
    info.has_acroform = 1;
    info.field_count = clamped(fields.size());
    auto const signatures = std::count_if(fields.begin(), fields.end(), is_signature);
    info.signature_field_count = clamped(static_cast<size_t>(signatures));
}

/// Widgets on pages with no /AcroForm in the catalog: PDFKit writes these, and viewers treat them as fields.
void describe_loose_widgets(std::vector<QPDFPageObjectHelper> &pages, zv_pdf_info &info) {
    size_t fields = 0, signatures = 0;
    for (auto &page : pages) {
        for (auto &widget : page.getAnnotations("/Widget")) {
            ++fields;
            signatures += widget.getObjectHandle().getKey("/FT").isNameAndEquals("/Sig") ? 1 : 0;
        }
    }
    info.field_count = clamped(fields);
    info.signature_field_count = clamped(signatures);
}

void describe_forms(QPDF &pdf, std::vector<QPDFPageObjectHelper> &pages, zv_pdf_info &info) {
    QPDFAcroFormDocumentHelper forms(pdf);
    if (forms.hasAcroForm()) {
        describe_acroform(forms, info);
    } else {
        describe_loose_widgets(pages, info);
    }
}

/// A second open with no password: a restrictions-only file passes it, a file with a real password does not.
bool opens_with_no_password(char const *path, zv_pdf_limits const *limits) {
    Secret const none(nullptr, 0);
    QPDF pdf;
    try {
        open_document(pdf, path, none, limits);
    } catch (QPDFExc const &error) {
        if (error.getErrorCode() == qpdf_e_password) {
            return false;
        }
        throw;
    }
    return true;
}

/// Everything about a document that opened.
void describe(QPDF &pdf, char const *path, Secret const &password, zv_pdf_limits const *limits, zv_pdf_info &info) {
    describe_encryption(pdf, info);
    info.owner_matched = info.handler != ZV_PDF_HANDLER_NONE && pdf.ownerPasswordMatched() ? 1 : 0;
    info.user_matched = info.handler != ZV_PDF_HANDLER_NONE && pdf.userPasswordMatched() ? 1 : 0;
    bool const opened_empty = password.empty();
    info.opens_without_password =
        info.handler == ZV_PDF_HANDLER_NONE || opened_empty || opens_with_no_password(path, limits) ? 1 : 0;
    auto pages = QPDFPageDocumentHelper(pdf).getAllPages();
    info.page_count = clamped(pages.size());
    describe_forms(pdf, pages, info);
    QPDFObjectHandle const root = pdf.getRoot();
    info.is_tagged = root.hasKey("/StructTreeRoot") ? 1 : 0;
    info.has_embedded_files = has_attachments(pdf, pages) ? 1 : 0;
    info.has_javascript = has_javascript(root, pages) ? 1 : 0;
    info.is_linearized = pdf.isLinearized() ? 1 : 0;
    describe_header(pdf, info);
}

/// What can be told about a document the shim did not open: its handler, and for the Standard one what it says.
void describe_refused(QPDF &pdf, zv_pdf_status status, zv_pdf_info &info) {
    if (status == ZV_PDF_WRONG_PASSWORD) {
        describe_encryption(pdf, info);
    } else {
        bool const standard = pdf.getTrailer().getKey("/Encrypt").getKey("/Filter").isNameAndEquals("/Standard");
        info.handler = standard ? ZV_PDF_HANDLER_UNKNOWN : ZV_PDF_HANDLER_OTHER;
    }
    describe_header(pdf, info);
}

/// Builds the document helpers so their own validation runs; true when the document has pages.
bool walk_helpers(QPDF &pdf, std::vector<QPDFPageObjectHelper> const &pages) {
    (void)QPDFAcroFormDocumentHelper(pdf).getFormFields();
    (void)QPDFEmbeddedFileDocumentHelper(pdf).getEmbeddedFiles();
    (void)QPDFPageLabelDocumentHelper(pdf).hasPageLabels();
    QPDFOutlineDocumentHelper outlines(pdf);
    (void)outlines.resolveNamedDest(QPDFObjectHandle::newString("zivlet-check"));
    if (pages.empty()) {
        return false;
    }
    (void)outlines.getOutlinesForPage(pages.front().getObjectHandle().getObjGen());
    return true;
}

/// Writes the whole document to nowhere with every stream decoded, so every object is read.
void write_to_nowhere(QPDF &pdf) {
    QPDFWriter writer(pdf);
    Pl_Discard discard;
    writer.setOutputPipeline(&discard);
    writer.setDecodeLevel(qpdf_dl_all);
    writer.setCompressStreams(false);
    writer.write();
}

/// Parses each page's content streams; false when any of them fails.
bool parse_pages(std::vector<QPDFPageObjectHelper> &pages) {
    bool every_page = true;
    for (auto &page : pages) {
        try {
            page.parseContents(nullptr);
        } catch (QPDFExc const &) {
            every_page = false;
        }
    }
    return every_page;
}

} // namespace

extern "C" zv_pdf_status zv_pdf_inspect(const char *path, const uint8_t *password, size_t password_length,
                                        const zv_pdf_limits *limits, zv_pdf_info *out) {
    if (path == nullptr || out == nullptr || (password == nullptr && password_length != 0)) {
        return ZV_PDF_INTERNAL;
    }
    return guarded(limits, [&]() -> zv_pdf_status {
        Secret secret(password, password_length);
        if (!secret.usable()) {
            return ZV_PDF_UNUSABLE_PASSWORD;
        }
        QPDF pdf;
        zv_pdf_info info{};
        try {
            open_document(pdf, path, secret, limits);
        } catch (QPDFExc const &) {
            zv_pdf_status const status = zivlet_pdf::status_of_current_exception();
            if (status == ZV_PDF_WRONG_PASSWORD || status == ZV_PDF_UNSUPPORTED_ENCRYPTION) {
                describe_refused(pdf, status, info);
                *out = info;
            }
            return status;
        }
        describe(pdf, path, secret, limits, info);
        *out = info;
        return ZV_PDF_OK;
    });
}

extern "C" zv_pdf_status zv_pdf_check(const char *path, const uint8_t *password, size_t password_length,
                                      const zv_pdf_limits *limits, uint32_t *warning_count) {
    if (path == nullptr || (password == nullptr && password_length != 0)) {
        return ZV_PDF_INTERNAL;
    }
    return guarded(limits, [&]() -> zv_pdf_status {
        Secret secret(password, password_length);
        if (!secret.usable()) {
            return ZV_PDF_UNUSABLE_PASSWORD;
        }
        QPDF pdf;
        open_document(pdf, path, secret, limits);
        auto pages = QPDFPageDocumentHelper(pdf).getAllPages();
        bool okay = walk_helpers(pdf, pages);
        write_to_nowhere(pdf);
        okay = parse_pages(pages) && okay;
        if (warning_count != nullptr) {
            *warning_count = clamped(pdf.numWarnings());
        }
        return okay ? ZV_PDF_OK : ZV_PDF_DAMAGED;
    });
}
