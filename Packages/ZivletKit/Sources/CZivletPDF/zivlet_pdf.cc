// The shim's shared parts (plan 20d C4, D-M7-16): the password copy, limits, silence and exception mapping.
#define __STDC_WANT_LIB_EXT1__ 1
#include <string.h>

#include "zivlet_pdf_private.hh"

#include <qpdf/Constants.h>
#include <qpdf/QPDFExc.hh>
#include <qpdf/QPDFLogger.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFSystemError.hh>
#include <qpdf/qpdf-c.h>

#include <array>
#include <new>
#include <stdexcept>
#include <utility>

namespace zivlet_pdf {

namespace {

/// The parameters zv_pdf_limits sets, in the order of its fields after max_pages.
constexpr std::array<qpdf_param_e, 5> limit_params = {
    qpdf_p_parser_max_nesting,
    qpdf_p_parser_max_container_size,
    qpdf_p_parser_max_container_size_damaged,
    qpdf_p_parser_max_errors,
    qpdf_p_max_stream_filters,
};

uint32_t read_param(qpdf_param_e param) {
    uint32_t value = 0;
    if (qpdf_global_get_uint32(param, &value) != qpdf_r_ok) {
        throw std::logic_error("qpdf refused a parameter read");
    }
    return value;
}

void write_param(qpdf_param_e param, uint32_t value) {
    if (qpdf_global_set_uint32(param, value) != qpdf_r_ok) {
        throw std::logic_error("qpdf refused a parameter");
    }
}

/// qpdf's own values, read once before the shim changes any (under call_mutex).
std::array<uint32_t, limit_params.size()> const &default_limits() {
    static std::array<uint32_t, limit_params.size()> const defaults = [] {
        std::array<uint32_t, limit_params.size()> values{};
        for (size_t i = 0; i < limit_params.size(); ++i) {
            values[i] = read_param(limit_params[i]);
        }
        return values;
    }();
    return defaults;
}

std::array<uint32_t, limit_params.size()> requested(zv_pdf_limits const *limits) {
    if (limits == nullptr) {
        return {};
    }
    return {limits->max_nesting, limits->max_container_size, limits->max_container_size_damaged, limits->max_errors,
            limits->max_stream_filters};
}

/// A logger whose info, warning and error output all go nowhere.
void silence(QPDFLogger &logger) {
    logger.setInfo(logger.discard());
    logger.setWarn(logger.discard());
    logger.setError(logger.discard());
}

std::shared_ptr<QPDFLogger> silent_logger() {
    static std::shared_ptr<QPDFLogger> const logger = [] {
        auto made = QPDFLogger::create();
        silence(*made);
        return made;
    }();
    return logger;
}

/// The limit-error count prepare_call saw; read and written only under call_mutex.
uint32_t limit_errors_before = 0;

zv_pdf_status status_of(QPDFExc const &error) {
    switch (error.getErrorCode()) {
    case qpdf_e_password:
        return ZV_PDF_WRONG_PASSWORD;
    case qpdf_e_system:
        return ZV_PDF_IO;
    case qpdf_e_internal:
        return ZV_PDF_INTERNAL;
    case qpdf_e_unsupported:
        // qpdf names the encryption dictionary for an unknown handler or R/V; other unsupported features are damage.
        return error.getObject() == "encryption dictionary" ? ZV_PDF_UNSUPPORTED_ENCRYPTION : ZV_PDF_DAMAGED;
    default:
        return ZV_PDF_DAMAGED;
    }
}

} // namespace

// Assigned in place, so the bytes land in one buffer and no temporary string holds a second copy.
Secret::Secret(const uint8_t *bytes, size_t length) : usable_(true) {
    if (bytes != nullptr && length != 0) {
        text_.assign(reinterpret_cast<char const *>(bytes), length);
    }
    usable_ = text_.find('\0') == std::string::npos;
}

Secret::~Secret() {
    if (!text_.empty()) {
        memset_s(text_.data(), text_.size(), 0, text_.size());
    }
}

std::mutex &call_mutex() {
    static std::mutex mutex;
    return mutex;
}

void prepare_call(zv_pdf_limits const *limits) {
    silence(*QPDFLogger::defaultLogger());
    auto const &defaults = default_limits();
    auto const wanted = requested(limits);
    for (size_t i = 0; i < limit_params.size(); ++i) {
        write_param(limit_params[i], wanted[i] != 0 ? wanted[i] : defaults[i]);
    }
    limit_errors_before = read_param(qpdf_p_limit_errors);
}

void throw_if_limits_hit() {
    if (read_param(qpdf_p_limit_errors) != limit_errors_before) {
        throw LimitExceeded{};
    }
}

zv_pdf_status status_after_limits(zv_pdf_status status) noexcept {
    if (status != ZV_PDF_OK && status != ZV_PDF_DAMAGED) {
        return status;
    }
    try {
        return read_param(qpdf_p_limit_errors) != limit_errors_before ? ZV_PDF_LIMIT : status;
    } catch (...) {
        return ZV_PDF_INTERNAL;
    }
}

zv_pdf_status status_of_current_exception() noexcept {
    try {
        throw;
    } catch (LimitExceeded const &) {
        return ZV_PDF_LIMIT;
    } catch (QPDFExc const &error) {
        return status_of(error);
    } catch (QPDFSystemError const &) {
        return ZV_PDF_IO;
    } catch (std::bad_alloc const &) {
        return ZV_PDF_LIMIT;
    } catch (std::logic_error const &) {
        return ZV_PDF_INTERNAL;
    } catch (std::exception const &) {
        // qpdf reports many structural faults as plain runtime errors.
        return ZV_PDF_DAMAGED;
    } catch (...) {
        return ZV_PDF_INTERNAL;
    }
}

void open_document(QPDF &pdf, char const *path, Secret const &password, zv_pdf_limits const *limits) {
    pdf.setLogger(silent_logger());
    pdf.setSuppressWarnings(true);
    pdf.processFile(path, password.c_str());
    throw_if_limits_hit();
    uint32_t const max_pages = limits == nullptr ? 0 : limits->max_pages;
    if (max_pages != 0 && QPDFPageDocumentHelper(pdf).getAllPages().size() > max_pages) {
        throw LimitExceeded{};
    }
}

} // namespace zivlet_pdf
