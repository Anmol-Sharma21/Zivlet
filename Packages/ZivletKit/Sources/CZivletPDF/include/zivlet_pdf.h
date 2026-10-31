// Zivlet's own small C interface to the qpdf library (plan 20d C4, D-M7-16). Swift imports only this header; qpdf's
// C++ headers stay inside the shim. It is linked only into ZivletWorker.
//
// Passwords arrive as bytes with a length, never as a command line. The shim copies them only for as long as qpdf
// needs them and overwrites that copy before it is freed; qpdf's own internal copies cannot be reached (best effort,
// G-M7-5). Nothing here prints: qpdf's loggers discard their output and its warnings are counted, never shown. No
// call reproduces qpdf's --check, --show-encryption or --json, which print a recovered user password.
//
// Every call runs under one lock, because qpdf's limits are process-wide settings.
#ifndef ZIVLET_PDF_H
#define ZIVLET_PDF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// What a call ended with. Every C++ exception inside the shim becomes one of these.
typedef enum zv_pdf_status {
    ZV_PDF_OK = 0,
    /// The password given (or no password) opens neither as user nor as owner.
    ZV_PDF_WRONG_PASSWORD = 1,
    /// qpdf could not read the file as a PDF, or the check found errors.
    ZV_PDF_DAMAGED = 2,
    /// A security handler other than the Standard one (certificates, a vendor's own).
    ZV_PDF_UNSUPPORTED_ENCRYPTION = 3,
    /// The file exceeds a limit of zv_pdf_limits.
    ZV_PDF_LIMIT = 4,
    /// The file could not be read or the output could not be written.
    ZV_PDF_IO = 5,
    /// Something already exists at the output path; the shim never overwrites.
    ZV_PDF_OUTPUT_EXISTS = 6,
    /// The password holds a NUL byte, which qpdf's C-string interface cannot carry.
    ZV_PDF_UNUSABLE_PASSWORD = 7,
    /// A missing argument or a fault inside qpdf.
    ZV_PDF_INTERNAL = 8,
} zv_pdf_status;

/// How a part of the file is encrypted.
typedef enum zv_pdf_method {
    ZV_PDF_METHOD_NONE = 0,
    ZV_PDF_METHOD_UNKNOWN = 1,
    ZV_PDF_METHOD_RC4 = 2,
    ZV_PDF_METHOD_AES128 = 3,
    ZV_PDF_METHOD_AES256 = 4,
    ZV_PDF_METHOD_IDENTITY = 5,
} zv_pdf_method;

/// Limits applied before each document is read. A zero leaves qpdf's own default in place.
typedef struct zv_pdf_limits {
    uint32_t max_pages;
    uint32_t max_nesting;
    uint32_t max_container_size;
    uint32_t max_container_size_damaged;
    uint32_t max_errors;
    uint32_t max_stream_filters;
} zv_pdf_limits;

/// The security handler of a document.
typedef enum zv_pdf_handler {
    /// Not encrypted.
    ZV_PDF_HANDLER_NONE = 0,
    ZV_PDF_HANDLER_STANDARD = 1,
    /// A handler other than the Standard one (certificates, a vendor's own).
    ZV_PDF_HANDLER_OTHER = 2,
    /// The Standard handler at a revision or version qpdf cannot read.
    ZV_PDF_HANDLER_UNKNOWN = 3,
} zv_pdf_handler;

/// What zv_pdf_inspect learns about a document. `allowed` holds the /P bits a file grants, in /P's own positions, read
/// by that file's revision. A refused open fills only the encryption facts, pdf_major, pdf_minor and warning_count.
typedef struct zv_pdf_info {
    zv_pdf_handler handler;
    int32_t revision;
    int32_t version;
    uint32_t allowed;
    zv_pdf_method streams;
    zv_pdf_method strings;
    zv_pdf_method files;
    int32_t owner_matched;
    int32_t user_matched;
    int32_t opens_without_password;
    uint32_t page_count;
    uint32_t warning_count;
    int32_t has_acroform;
    uint32_t field_count;
    uint32_t signature_field_count;
    int32_t is_tagged;
    int32_t has_embedded_files;
    int32_t has_javascript;
    int32_t is_linearized;
    int32_t pdf_major;
    int32_t pdf_minor;
} zv_pdf_info;

/// What zv_pdf_write does with the encryption of its input.
typedef enum zv_pdf_mode {
    /// The same encryption as the input (none stays none).
    ZV_PDF_MODE_PRESERVE = 0,
    /// No encryption at all.
    ZV_PDF_MODE_DECRYPT = 1,
    /// AES-256, revision 6, with the passwords and permissions of zv_pdf_r6_params.
    ZV_PDF_MODE_ENCRYPT_R6 = 2,
} zv_pdf_mode;

/// Printing allowed by an R6 file.
typedef enum zv_pdf_print {
    ZV_PDF_PRINT_FULL = 0,
    ZV_PDF_PRINT_LOW = 1,
    ZV_PDF_PRINT_NONE = 2,
} zv_pdf_print;

/// The passwords (bytes and length, no NUL inside) and permissions of an R6 output.
typedef struct zv_pdf_r6_params {
    const uint8_t *user;
    size_t user_length;
    const uint8_t *owner;
    size_t owner_length;
    int32_t allow_accessibility;
    int32_t allow_extract;
    int32_t allow_assemble;
    int32_t allow_annotate_and_form;
    int32_t allow_form_filling;
    int32_t allow_modify_other;
    zv_pdf_print print;
    int32_t encrypt_metadata;
} zv_pdf_r6_params;

/// Opens `path` with the password (NULL or length 0: none) and fills `out`. On ZV_PDF_WRONG_PASSWORD and
/// ZV_PDF_UNSUPPORTED_ENCRYPTION it still fills what can be known without opening the file (see zv_pdf_info).
zv_pdf_status zv_pdf_inspect(const char *path, const uint8_t *password, size_t password_length,
                             const zv_pdf_limits *limits, zv_pdf_info *out);

/// Reads every object and decodes every stream (written to nowhere), builds the document helpers and parses every
/// page's content, without printing anything. `warning_count` may be NULL.
zv_pdf_status zv_pdf_check(const char *path, const uint8_t *password, size_t password_length,
                           const zv_pdf_limits *limits, uint32_t *warning_count);

/// Writes `in_path`, opened with the password, to `out_path`, which must not exist. A failed write removes what it
/// wrote. `params` is read only in ZV_PDF_MODE_ENCRYPT_R6.
zv_pdf_status zv_pdf_write(const char *in_path, const uint8_t *password, size_t password_length,
                           const zv_pdf_limits *limits, zv_pdf_mode mode, const zv_pdf_r6_params *params,
                           const char *out_path);

#ifdef __cplusplus
}
#endif

#endif
