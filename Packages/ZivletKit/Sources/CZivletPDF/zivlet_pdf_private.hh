// The shim's shared parts (plan 20d C4): the password copy, the call guard and the silent document opener.
#ifndef ZIVLET_PDF_PRIVATE_HH
#define ZIVLET_PDF_PRIVATE_HH

#include "zivlet_pdf.h"

#include <qpdf/QPDF.hh>

#include <cstdint>
#include <mutex>
#include <string>

namespace zivlet_pdf {

/// A NUL-terminated copy of a password for qpdf's C-string interface. Its bytes are overwritten with zeros (memset_s,
/// which the compiler may not drop) before the memory is freed. It is never copied or moved.
class Secret {
  public:
    Secret(const uint8_t *bytes, size_t length);
    ~Secret();
    Secret(Secret const &) = delete;
    Secret &operator=(Secret const &) = delete;

    /// No NUL byte inside, so qpdf sees the whole password.
    bool usable() const { return usable_; }
    bool empty() const { return text_.empty(); }
    char const *c_str() const { return text_.c_str(); }

  private:
    std::string text_;
    bool usable_;
};

/// Thrown inside the shim when a document exceeds one of zv_pdf_limits, or qpdf reports hitting one of its own.
struct LimitExceeded {};

/// The one lock every call holds: qpdf's limits and its default logger are process-wide.
std::mutex &call_mutex();

/// Silences qpdf's default logger and applies `limits` (a zero keeps qpdf's default). Remembers how many limit errors
/// qpdf had counted, so throw_if_limits_hit can tell whether this call added one.
void prepare_call(zv_pdf_limits const *limits);

/// Throws LimitExceeded when qpdf counted a limit error since prepare_call.
void throw_if_limits_hit();

/// The status for the exception being handled; called only inside a catch block.
zv_pdf_status status_of_current_exception() noexcept;

/// Opens `path` into `pdf` with `password`, warnings counted and never shown, output discarded; then refuses a
/// document over the page limit. Throws what qpdf throws, or LimitExceeded.
void open_document(QPDF &pdf, char const *path, Secret const &password, zv_pdf_limits const *limits);

/// `status`, or ZV_PDF_LIMIT when qpdf counted a limit error since prepare_call: qpdf either carries on after one or
/// gives up with an error of its own, so both success and damage may be a limit underneath.
zv_pdf_status status_after_limits(zv_pdf_status status) noexcept;

/// Runs `body` under call_mutex with the limits applied; every exception becomes a status, and a limit qpdf hit on
/// the way becomes ZV_PDF_LIMIT.
template <typename Body> zv_pdf_status guarded(zv_pdf_limits const *limits, Body &&body) noexcept {
    std::lock_guard<std::mutex> lock(call_mutex());
    zv_pdf_status status = ZV_PDF_INTERNAL;
    try {
        prepare_call(limits);
        status = body();
    } catch (...) {
        status = status_of_current_exception();
    }
    return status_after_limits(status);
}

} // namespace zivlet_pdf

#endif
