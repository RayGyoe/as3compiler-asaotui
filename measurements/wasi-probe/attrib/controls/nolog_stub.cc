// Seam-side replacement for yoga/debug/Log.cpp + yoga/debug/AssertFatal.cpp.
//
// WHY: grep shows Yoga has NO YG_ENABLE_LOGGING / YG_ENABLE_EVENTS / NDEBUG
// switch that removes the log/assert path -- Log.cpp's default logger always
// calls vfprintf, and AssertFatal.cpp always calls std::terminate under
// -fno-exceptions. The only way to keep them out of the link (without patching
// Yoga upstream) is to DEFINE the same symbols in a seam TU and drop the two
// upstream TUs from the archive, so the linker never extracts them.
//
// Behaviour: identical to upstream for the pass path (assertions still call
// the same fatal handlers on failure); only the *formatting* is dropped -- the
// message is discarded instead of vfprintf'd. This is an experiment to size
// the vfprintf/terminate payload, not a shipping recommendation.
#include <cstdlib>
#include <cstdarg>
#include <yoga/Yoga.h>
#include <yoga/debug/Log.h>
#include <yoga/debug/AssertFatal.h>
#include <yoga/node/Node.h>
#include <yoga/config/Config.h>

namespace facebook::yoga {

[[noreturn]] void fatalWithMessage(const char* /*message*/) { std::abort(); }

void assertFatal(bool /*c*/, const char* /*m*/) {}
void assertFatalWithNode(const yoga::Node* /*n*/, bool /*c*/, const char* /*m*/) {}
void assertFatalWithConfig(const yoga::Config* /*c*/, bool /*c2*/, const char* /*m*/) {}

void log(LogLevel /*level*/, const char* /*format*/, ...) noexcept {}
void log(const yoga::Node* /*node*/, LogLevel /*level*/, const char* /*format*/, ...) noexcept {}
void log(const yoga::Config* /*config*/, LogLevel /*level*/, const char* /*format*/, ...) noexcept {}

YGLogger getDefaultLogger() {
  return [](const YGConfigConstRef, const YGNodeConstRef, YGLogLevel,
            const char*, va_list) -> int { return 0; };
}

} // namespace facebook::yoga
