#+build wasm32, wasm64p32
// RuiShin: Odin implementation of sokol_log's `slog_func` for the pure-WASM target.
//
// The C sokol_log needs <emscripten/emscripten.h> (EM_JS) on the web; there is no Emscripten
// here. This has the same signature, so `logger = {func = slog.func}` works unchanged.
// Output goes through odin.js: stdout -> console.log, stderr -> console.error.
package sokol_log

import "base:runtime"
import "core:fmt"

foreign import odin_env "odin_env"

// The same import Odin's own runtime uses for stdout/stderr (odin.js: fd 1 -> console.log,
// fd 2 -> console.error).
@(default_calling_convention = "contextless")
foreign odin_env {
	write :: proc(fd: u32, p: []byte) ---
}

// Plug this into the `logger.func` item of any sokol setup call.
func :: proc "c" (tag: cstring, log_level: u32, log_item: u32, message: cstring, line_nr: u32, filename: cstring, user_data: rawptr) {
	context = runtime.default_context()
	level_str: string
	switch log_level {
	case 0: level_str = "panic"
	case 1: level_str = "error"
	case 2: level_str = "warning"
	case: level_str = "info"
	}
	// level 0/1 -> stderr (console.error); the rest -> stdout (console.log)
	fd: u32 = 1 if log_level >= 2 else 2
	buf: [1024]u8
	line: string
	if tag == nil {
		line = fmt.bprintf(buf[:], "[%s][id:%d] %s:%d: %s\n", level_str, log_item, filename, line_nr, message)
	} else {
		line = fmt.bprintf(buf[:], "[%s][%s][id:%d] %s:%d: %s\n", level_str, tag, log_item, filename, line_nr, message)
	}
	write(fd, transmute([]byte)line)
	if log_level == 0 {
		runtime.trap()
	}
}
