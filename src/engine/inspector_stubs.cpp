// Inspector callback stubs - C implementations required by v8-zig bindings
// See binding.cpp comment: "zig project should provide those implementations with C-like functions"

#include <cstdint>
#include <cstddef>

// Forward declarations matching binding.cpp types
struct v8_inspector__Client__IMPL;
struct v8_inspector__Channel__IMPL;

namespace v8 {
    class Isolate;
    namespace internal { }
}

namespace v8_inspector {
    class StringView {};
    class V8StackTrace {};
}

// Client callback stubs - extern "C" to avoid C++ name mangling
extern "C" {

int64_t v8_inspector__Client__IMPL__generateUniqueId(
    v8_inspector__Client__IMPL* self, void* data) {
    return 0;
}

void v8_inspector__Client__IMPL__runMessageLoopOnPause(
    v8_inspector__Client__IMPL* self, void* data, int contextGroupId) {
}

void v8_inspector__Client__IMPL__quitMessageLoopOnPause(
    v8_inspector__Client__IMPL* self, void* data) {
}

void v8_inspector__Client__IMPL__runIfWaitingForDebugger(
    v8_inspector__Client__IMPL* self, void* data, int contextGroupId) {
}

void v8_inspector__Client__IMPL__consoleAPIMessage(
    v8_inspector__Client__IMPL* self, void* data, int contextGroupId,
    int level,
    const v8_inspector::StringView* message,
    const v8_inspector::StringView* url, unsigned lineNumber,
    unsigned columnNumber, v8_inspector::V8StackTrace* stackTrace) {
}

void v8_inspector__Client__IMPL__ensureDefaultContextInGroup(
    v8_inspector__Client__IMPL* self, void* data, int contextGroupId) {
}

// Channel callback stubs
void v8_inspector__Channel__IMPL__sendResponse(
    v8_inspector__Channel__IMPL* self, void* data,
    int callId, const char* message, size_t length) {
}

void v8_inspector__Channel__IMPL__sendNotification(
    v8_inspector__Channel__IMPL* self, void* data,
    const char* msg, size_t length) {
}

void v8_inspector__Channel__IMPL__flushProtocolNotifications(
    v8_inspector__Channel__IMPL* self, void* data) {
}

} // extern "C"
