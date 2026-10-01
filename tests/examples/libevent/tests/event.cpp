#ifdef _WIN32
#include <winsock2.h>
#endif

#include <event2/buffer.h>
#include <event2/event.h>
#include <event2/http.h>

#include <cstring>
#include <cstdio>

static void fired(evutil_socket_t, short, void* arg) {
    ++*static_cast<int*>(arg);
}

int main() {
#ifdef _WIN32
    WSADATA winsock;
    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) return 1;
#endif
    event_base* base = event_base_new();
    if (!base) {
#ifdef _WIN32
        WSACleanup();
#endif
        return 1;
    }
    int count = 0;
    timeval delay = {0, 0};
    const int scheduled = event_base_once(base, -1, EV_TIMEOUT, fired, &count, &delay);
    const int dispatched = scheduled == 0 ? event_base_loop(base, EVLOOP_ONCE) : -1;
    bool ok = scheduled == 0 && dispatched == 0 && count == 1;
    if (!ok) std::fprintf(stderr, "event loop: schedule=%d dispatch=%d count=%d\n", scheduled, dispatched, count);

    evbuffer* buffer = evbuffer_new();
    if (!buffer) {
        event_base_free(base);
#ifdef _WIN32
        WSACleanup();
#endif
        return 1;
    }
    const char text[] = "libevent";
    char out[sizeof(text)] = {};
    const bool buffer_ok = evbuffer_add(buffer, text, sizeof(text) - 1) == 0
        && evbuffer_remove(buffer, out, sizeof(text) - 1) == sizeof(text) - 1
        && std::strcmp(out, text) == 0 && evbuffer_get_length(buffer) == 0;
    if (!buffer_ok) std::fprintf(stderr, "buffer round trip failed\n");
    ok = ok && buffer_ok;

    evhttp* http = evhttp_new(base);
    ok = ok && http != nullptr;
    if (!http) std::fprintf(stderr, "evhttp_new failed\n");
    if (http) evhttp_free(http);
    evbuffer_free(buffer);
    event_base_free(base);
#ifdef _WIN32
    WSACleanup();
#endif
    return ok ? 0 : 1;
}
