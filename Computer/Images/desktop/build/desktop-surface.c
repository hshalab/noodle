// Serves the desktop to Noodle Computer over vsock, so agents and remote viewers
// can see and use it without a window on the Mac. One client at a time.
//
// Every number is little-endian. Requests start with one byte:
//   1 frame                      reply: u32 width, u32 height, u32 tiles, then per
//                                tile u32 x, y, w, h and w*h BGRX pixels. Only tiles
//                                that changed since the last reply are sent.
//   2 pointer u8 phase, i32 x, i32 y   phase 0 move, 1 press, 2 drag, 3 release
//   3 scroll  i32 x, i32 y, i32 dx, i32 dy   pixels; about 40 make one wheel step
//   4 key     u32 keysym
//   5 text    u32 length, UTF-8 bytes
//   6 paste   u32 length, UTF-8 bytes   put on the clipboard, then paste into the focused app
//   7 copy                       reply: u32 length, UTF-8 bytes of what the focused app copied
// The clipboard moves only on these two requests: the guest never sees the Mac's otherwise.
#define _GNU_SOURCE
#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xcomposite.h>
#include <linux/vm_sockets.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <unistd.h>

enum { TILE = 64, CLIPBOARD_LIMIT = 1 << 20 };

static Display *display;
static XShmSegmentInfo shm;
static XImage *image;
static uint32_t *previous;
static int width, height;
// Shared memory is faster, but a server may refuse it; then every frame is copied.
static int use_shm = 1;
static int x_error;

// Xlib's default handler ends the process; one failed request must not end the service.
static int record_error(Display *failing, XErrorEvent *event) {
    (void)failing;
    x_error = event->error_code;
    return 0;
}

static int full(int fd, void *buffer, size_t length, int writing) {
    char *bytes = buffer;
    while (length) {
        ssize_t done = writing ? write(fd, bytes, length) : read(fd, bytes, length);
        if (done <= 0) return -1;
        bytes += done;
        length -= (size_t)done;
    }
    return 0;
}

static void release_image(void) {
    free(previous);
    previous = NULL;
    if (!image) return;
    XShmDetach(display, &shm);
    XDestroyImage(image);
    shmdt(shm.shmaddr);
    image = NULL;
}

static int attach_shared_image(void) {
    image = XShmCreateImage(display, DefaultVisual(display, DefaultScreen(display)), 24, ZPixmap, NULL, &shm,
                            (unsigned)width, (unsigned)height);
    if (!image) return -1;
    shm.shmid = shmget(IPC_PRIVATE, (size_t)image->bytes_per_line * (size_t)height, IPC_CREAT | 0600);
    shm.shmaddr = image->data = shm.shmid < 0 ? (char *)-1 : shmat(shm.shmid, NULL, 0);
    shm.readOnly = False;
    x_error = 0;
    if (shm.shmaddr != (char *)-1) {
        XShmAttach(display, &shm);
        XSync(display, False);
    }
    if (shm.shmid >= 0) shmctl(shm.shmid, IPC_RMID, NULL);
    if (shm.shmaddr == (char *)-1 || x_error) {
        if (shm.shmaddr != (char *)-1) shmdt(shm.shmaddr);
        image->data = NULL;
        XDestroyImage(image);
        image = NULL;
        return -1;
    }
    return 0;
}

// The compositor draws the finished screen into its overlay window; without one
// the root window holds it. Never take the overlay ourselves: that maps it.
static Window source(void) {
    Window root = DefaultRootWindow(display);
    Atom compositor = XInternAtom(display, "_NET_WM_CM_S0", False);
    if (XGetSelectionOwner(display, compositor) != None) {
        Window overlay = XCompositeGetOverlayWindow(display, root);
        XCompositeReleaseOverlayWindow(display, root);
        return overlay;
    }
    return root;
}

static int send_frame(int fd) {
    XWindowAttributes attributes;
    XGetWindowAttributes(display, DefaultRootWindow(display), &attributes);
    if (!previous || attributes.width != width || attributes.height != height) {
        release_image();
        width = attributes.width;
        height = attributes.height;
        if (use_shm && attach_shared_image()) {
            fputs("desktop-surface: shared memory refused; copying frames instead\n", stderr);
            use_shm = 0;
        }
        previous = calloc((size_t)width * (size_t)height, 4);
        // Nothing matches an all-zero first frame reliably, so mark every pixel stale.
        memset(previous, 0xff, (size_t)width * (size_t)height * 4);
    }
    XImage *grab = image;
    x_error = 0;
    if (use_shm) {
        if (!XShmGetImage(display, source(), image, 0, 0, AllPlanes)) return -1;
    } else if (!(grab = XGetImage(display, source(), 0, 0, (unsigned)width, (unsigned)height, AllPlanes, ZPixmap))) {
        return -1;
    }
    if (x_error || grab->bits_per_pixel != 32) {
        if (grab != image) XDestroyImage(grab);
        return -1;
    }
    uint32_t count = 0, header[3] = {(uint32_t)width, (uint32_t)height, 0};
    int columns = (width + TILE - 1) / TILE, rows = (height + TILE - 1) / TILE;
    unsigned char *changed = calloc((size_t)columns * (size_t)rows, 1);
    int stride = grab->bytes_per_line / 4;
    uint32_t *pixels = (uint32_t *)grab->data;
    for (int row = 0; row < rows; row++)
        for (int column = 0; column < columns; column++) {
            int x = column * TILE, y = row * TILE, w = width - x < TILE ? width - x : TILE, h = height - y < TILE ? height - y : TILE;
            for (int line = y; line < y + h; line++)
                if (memcmp(pixels + line * stride + x, previous + line * width + x, (size_t)w * 4)) {
                    changed[row * columns + column] = 1;
                    count++;
                    break;
                }
        }
    header[2] = count;
    int failed = full(fd, header, sizeof header, 1);
    for (int tile = 0; !failed && tile < columns * rows; tile++) {
        if (!changed[tile]) continue;
        int x = (tile % columns) * TILE, y = (tile / columns) * TILE;
        uint32_t w = (uint32_t)(width - x < TILE ? width - x : TILE), h = (uint32_t)(height - y < TILE ? height - y : TILE);
        uint32_t rect[4] = {(uint32_t)x, (uint32_t)y, w, h};
        failed = full(fd, rect, sizeof rect, 1);
        for (uint32_t line = 0; !failed && line < h; line++) {
            uint32_t *from = pixels + (y + (int)line) * stride + x;
            memcpy(previous + (y + (int)line) * width + x, from, w * 4);
            failed = full(fd, from, w * 4, 1);
        }
    }
    free(changed);
    if (grab != image) XDestroyImage(grab);
    return failed;
}

static void press(unsigned button) {
    XTestFakeButtonEvent(display, button, True, CurrentTime);
    XTestFakeButtonEvent(display, button, False, CurrentTime);
}

// Types one keysym, borrowing a spare keycode when the layout has none for it.
static void type_keysym(KeySym keysym) {
    KeyCode code = XKeysymToKeycode(display, keysym);
    int borrowed = 0, shifted = 0;
    if (code) {
        shifted = XkbKeycodeToKeysym(display, code, 0, 0) != keysym && XkbKeycodeToKeysym(display, code, 0, 1) == keysym;
    } else {
        int low, high, per;
        XDisplayKeycodes(display, &low, &high);
        KeySym *map = XGetKeyboardMapping(display, (KeyCode)low, high - low + 1, &per);
        for (int candidate = high; candidate >= low && !code; candidate--) {
            int empty = 1;
            for (int i = 0; i < per; i++) empty &= map[(candidate - low) * per + i] == NoSymbol;
            if (empty) code = (KeyCode)candidate;
        }
        XFree(map);
        if (!code) return;
        KeySym both[2] = {keysym, keysym};
        XChangeKeyboardMapping(display, code, 2, both, 1);
        XSync(display, False);
        borrowed = 1;
    }
    KeyCode shift = XKeysymToKeycode(display, XK_Shift_L);
    if (shifted) XTestFakeKeyEvent(display, shift, True, CurrentTime);
    XTestFakeKeyEvent(display, code, True, CurrentTime);
    XTestFakeKeyEvent(display, code, False, CurrentTime);
    if (shifted) XTestFakeKeyEvent(display, shift, False, CurrentTime);
    if (borrowed) {
        XSync(display, False);
        KeySym none[2] = {NoSymbol, NoSymbol};
        XChangeKeyboardMapping(display, code, 2, none, 1);
    }
}

static void type_text(const unsigned char *text, uint32_t length) {
    for (uint32_t i = 0; i < length;) {
        uint32_t point = text[i], extra = point >= 0xf0 ? 3 : point >= 0xe0 ? 2 : point >= 0xc0 ? 1 : 0;
        point &= extra == 3 ? 0x07 : extra == 2 ? 0x0f : extra == 1 ? 0x1f : 0x7f;
        for (uint32_t k = 1; k <= extra && i + k < length; k++) point = (point << 6) | (text[i + k] & 0x3f);
        i += extra + 1;
        KeySym keysym = point == '\n' ? XK_Return : point == '\t' ? XK_Tab
            : point < 0x100 ? (KeySym)point : (KeySym)(0x01000000 | point);
        type_keysym(keysym);
    }
}

static void chord(KeySym modifier, KeySym key) {
    KeyCode held = XKeysymToKeycode(display, modifier), code = XKeysymToKeycode(display, key);
    XTestFakeKeyEvent(display, held, True, CurrentTime);
    XTestFakeKeyEvent(display, code, True, CurrentTime);
    XTestFakeKeyEvent(display, code, False, CurrentTime);
    XTestFakeKeyEvent(display, held, False, CurrentTime);
    XSync(display, False);
}

// Terminals keep Ctrl+C for interrupting and paste from the selection, so they get their own keys.
static int focused_is_terminal(void) {
    Window root = DefaultRootWindow(display), focused = None;
    Atom active = XInternAtom(display, "_NET_ACTIVE_WINDOW", False), type;
    int format;
    unsigned long count, after;
    unsigned char *value = NULL;
    if (XGetWindowProperty(display, root, active, 0, 1, False, XA_WINDOW, &type, &format, &count, &after, &value) == Success && value) {
        if (count) focused = *(Window *)value;
        XFree(value);
    }
    XClassHint hint = {0};
    if (!focused || !XGetClassHint(display, focused, &hint)) return 0;
    int terminal = 0;
    for (const char *name = hint.res_class; name && !terminal; name = name == hint.res_class ? hint.res_name : NULL)
        terminal = strcasestr(name, "term") || strcasestr(name, "kitty");
    XFree(hint.res_name);
    XFree(hint.res_class);
    return terminal;
}

static int take_selection(const char *selection, const unsigned char *text, uint32_t length) {
    char command[64];
    snprintf(command, sizeof command, "xclip -selection %s -in", selection);
    FILE *pipe = popen(command, "w");
    if (!pipe) return -1;
    fwrite(text, 1, length, pipe);
    return pclose(pipe) == 0 ? 0 : -1;
}

static uint32_t read_selection(const char *selection, unsigned char *text) {
    char command[64];
    snprintf(command, sizeof command, "xclip -selection %s -out 2>/dev/null", selection);
    FILE *pipe = popen(command, "r");
    if (!pipe) return 0;
    size_t length = fread(text, 1, CLIPBOARD_LIMIT, pipe);
    pclose(pipe);
    return (uint32_t)length;
}

static int serve(int fd) {
    for (;;) {
        unsigned char op;
        if (full(fd, &op, 1, 0)) return 0;
        int32_t values[4];
        switch (op) {
        case 1:
            if (send_frame(fd)) return 0;
            break;
        case 2: {
            unsigned char phase;
            if (full(fd, &phase, 1, 0) || full(fd, values, 8, 0)) return 0;
            XTestFakeMotionEvent(display, -1, values[0], values[1], CurrentTime);
            if (phase == 1 || phase == 3) XTestFakeButtonEvent(display, 1, phase == 1, CurrentTime);
            break;
        }
        case 3:
            if (full(fd, values, 16, 0)) return 0;
            XTestFakeMotionEvent(display, -1, values[0], values[1], CurrentTime);
            for (int steps = abs(values[3]) / 40 + (values[3] != 0); values[3] && steps--;) press(values[3] > 0 ? 5 : 4);
            for (int steps = abs(values[2]) / 40 + (values[2] != 0); values[2] && steps--;) press(values[2] > 0 ? 7 : 6);
            break;
        case 4: {
            uint32_t keysym;
            if (full(fd, &keysym, 4, 0)) return 0;
            type_keysym(keysym);
            break;
        }
        case 5: {
            uint32_t length;
            if (full(fd, &length, 4, 0) || length > 65536) return 0;
            unsigned char *text = malloc(length ? length : 1);
            if (full(fd, text, length, 0)) { free(text); return 0; }
            type_text(text, length);
            free(text);
            break;
        }
        case 6: {
            uint32_t length;
            if (full(fd, &length, 4, 0) || length > CLIPBOARD_LIMIT) return 0;
            unsigned char *text = malloc(length ? length : 1);
            if (full(fd, text, length, 0)) { free(text); return 0; }
            int terminal = focused_is_terminal();
            if (!take_selection("clipboard", text, length) && !take_selection("primary", text, length)) {
                usleep(100000);
                if (terminal) chord(XK_Shift_L, XK_Insert); else chord(XK_Control_L, XK_v);
            }
            free(text);
            break;
        }
        case 7: {
            unsigned char *text = malloc(CLIPBOARD_LIMIT);
            uint32_t length = 0;
            if (focused_is_terminal()) {
                length = read_selection("primary", text);
            } else {
                chord(XK_Control_L, XK_c);
                usleep(200000);
                length = read_selection("clipboard", text);
            }
            int failed = full(fd, &length, 4, 1) || full(fd, text, length, 1);
            free(text);
            if (failed) return 0;
            break;
        }
        default:
            return 0;
        }
        XFlush(display);
    }
}

int main(int argc, char **argv) {
    unsigned port = argc > 1 ? (unsigned)atoi(argv[1]) : 5100;
    display = XOpenDisplay(NULL);
    if (!display) { fputs("desktop-surface: cannot open the display\n", stderr); return 1; }
    XSetErrorHandler(record_error);
    int server = socket(AF_VSOCK, SOCK_STREAM, 0);
    // Only the Mac side of the VM can reach a guest vsock port.
    struct sockaddr_vm address = {.svm_family = AF_VSOCK, .svm_port = port, .svm_cid = VMADDR_CID_ANY};
    if (server < 0 || bind(server, (struct sockaddr *)&address, sizeof address) || listen(server, 1)) {
        perror("desktop-surface");
        return 1;
    }
    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        release_image();
        serve(client);
        close(client);
    }
}
