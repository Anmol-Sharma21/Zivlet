// zv_pdf_write (plan 20d C4): preserve, decrypt or encrypt as AES-256 R6. The output is created exclusively (never
// over an existing file) and removed again when the write fails.
#include "zivlet_pdf_private.hh"

#include <qpdf/QPDFWriter.hh>

#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <memory>
#include <unistd.h>

using zivlet_pdf::guarded;
using zivlet_pdf::open_document;
using zivlet_pdf::Secret;

namespace {

/// The R6 passwords as C strings for qpdf, wiped when the write ends.
struct R6Secrets {
    Secret user;
    Secret owner;
    explicit R6Secrets(zv_pdf_r6_params const &params)
        : user(params.user, params.user_length), owner(params.owner, params.owner_length) {}
    bool usable() const { return user.usable() && owner.usable(); }
};

qpdf_r3_print_e print_of(zv_pdf_print print) {
    switch (print) {
    case ZV_PDF_PRINT_LOW:
        return qpdf_r3p_low;
    case ZV_PDF_PRINT_NONE:
        return qpdf_r3p_none;
    default:
        return qpdf_r3p_full;
    }
}

void configure(QPDFWriter &writer, zv_pdf_mode mode, zv_pdf_r6_params const *params, R6Secrets const *secrets) {
    switch (mode) {
    case ZV_PDF_MODE_DECRYPT:
        writer.setPreserveEncryption(false);
        break;
    case ZV_PDF_MODE_ENCRYPT_R6:
        writer.setR6EncryptionParameters(secrets->user.c_str(), secrets->owner.c_str(), params->allow_accessibility != 0,
                                         params->allow_extract != 0, params->allow_assemble != 0,
                                         params->allow_annotate_and_form != 0, params->allow_form_filling != 0,
                                         params->allow_modify_other != 0, print_of(params->print),
                                         params->encrypt_metadata != 0);
        break;
    default:
        break;
    }
}

/// Creates `path` for writing; fails with ZV_PDF_OUTPUT_EXISTS when anything is there already.
zv_pdf_status create_output(char const *path, FILE **file) {
    int const fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0666);
    if (fd < 0) {
        return errno == EEXIST ? ZV_PDF_OUTPUT_EXISTS : ZV_PDF_IO;
    }
    *file = fdopen(fd, "wb");
    if (*file == nullptr) {
        close(fd);
        unlink(path);
        return ZV_PDF_IO;
    }
    return ZV_PDF_OK;
}

bool known_mode(zv_pdf_mode mode) {
    return mode == ZV_PDF_MODE_PRESERVE || mode == ZV_PDF_MODE_DECRYPT || mode == ZV_PDF_MODE_ENCRYPT_R6;
}

} // namespace

extern "C" zv_pdf_status zv_pdf_write(const char *in_path, const uint8_t *password, size_t password_length,
                                      const zv_pdf_limits *limits, zv_pdf_mode mode, const zv_pdf_r6_params *params,
                                      const char *out_path) {
    if (in_path == nullptr || out_path == nullptr || (password == nullptr && password_length != 0) ||
        !known_mode(mode) || (mode == ZV_PDF_MODE_ENCRYPT_R6 && params == nullptr)) {
        return ZV_PDF_INTERNAL;
    }
    return guarded(limits, [&]() -> zv_pdf_status {
        Secret secret(password, password_length);
        std::unique_ptr<R6Secrets> secrets;
        if (mode == ZV_PDF_MODE_ENCRYPT_R6) {
            secrets = std::make_unique<R6Secrets>(*params);
        }
        if (!secret.usable() || (secrets && !secrets->usable())) {
            return ZV_PDF_UNUSABLE_PASSWORD;
        }
        QPDF pdf;
        open_document(pdf, in_path, secret, limits);
        FILE *file = nullptr;
        if (zv_pdf_status const created = create_output(out_path, &file); created != ZV_PDF_OK) {
            return created;
        }
        try {
            QPDFWriter writer(pdf, out_path, file, true);
            configure(writer, mode, params, secrets.get());
            writer.write();
            zivlet_pdf::throw_if_limits_hit();
        } catch (...) {
            unlink(out_path);
            throw;
        }
        return ZV_PDF_OK;
    });
}
