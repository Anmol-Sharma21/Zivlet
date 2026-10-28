// zv_pdf_inspect and zv_pdf_check (plan 20d C4). The check walks the document as qpdf's --check does, but prints
// nothing and never shows the encryption (which would print a recovered user password, D-M7-16).
#include "zivlet_pdf_private.hh"

#include <qpdf/Pl_Discard.hh>
#include <qpdf/QPDFAcroFormDocumentHelper.hh>
#include <qpdf/QPDFEmbeddedFileDocumentHelper.hh>
#include <qpdf/QPDFExc.hh>
#include <qpdf/QPDFObjectHandle.hh>
#include <qpdf/QPDFOutlineDocumentHelper.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFPageLabelDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>

#include <limits>

using zivlet_pdf::guarded;
using zivlet_pdf::open_document;
using zivlet_pdf::Secret;

namespace {

zv_pdf_method method_of(QPDF::encryption_method_e method) {
    switch (method) {
    case QPDF::e_none:
        return ZV_PDF_METHOD_NONE;
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

void describe(QPDF &pdf, zv_pdf_info &info) {
    int revision = 0, permissions = 0, version = 0;
    QPDF::encryption_method_e streams = QPDF::e_none, strings = QPDF::e_none, files = QPDF::e_none;
    bool const encrypted = pdf.isEncrypted(revision, permissions, version, streams, strings, files);
    if (encrypted && version < 4) {
        // Before V 4 there are no crypt filters and everything is RC4; qpdf leaves the methods at none then.
        streams = strings = files = QPDF::e_rc4;
    }
    info.encrypted = encrypted ? 1 : 0;
    info.revision = encrypted ? revision : 0;
    info.version = encrypted ? version : 0;
    info.permissions = encrypted ? permissions : -1;
    info.streams = encrypted ? method_of(streams) : ZV_PDF_METHOD_NONE;
    info.strings = encrypted ? method_of(strings) : ZV_PDF_METHOD_NONE;
    info.files = encrypted ? method_of(files) : ZV_PDF_METHOD_NONE;
    info.owner_matched = encrypted && pdf.ownerPasswordMatched() ? 1 : 0;
    info.user_matched = encrypted && pdf.userPasswordMatched() ? 1 : 0;
    info.page_count = clamped(QPDFPageDocumentHelper(pdf).getAllPages().size());
    info.warning_count = clamped(pdf.numWarnings());
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
        open_document(pdf, path, secret, limits);
        zv_pdf_info info{};
        describe(pdf, info);
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
