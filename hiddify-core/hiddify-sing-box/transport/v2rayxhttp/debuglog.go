//go:build hiddify_netdebug

package xhttp

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// xhttpDebugLog is diagnostic instrumentation for XHTTP-layer failures: the
// generic sing-box connection wrapper only ever logs a vague "closed pipe"
// for every kind of failure, with the real net/http error or HTTP status
// code discarded. Writes straight to a fixed file instead of going through
// sing-box's own logger plumbing (which isn't threaded down to
// DefaultDialerClient). Only compiled in with the hiddify_netdebug build tag
// -- release builds get the no-op in debuglog_stub.go instead.
var xhttpDebugLogOnce sync.Once
var xhttpDebugLogPath string

func xhttpDebugLog(format string, args ...any) {
	xhttpDebugLogOnce.Do(func() {
		dir := os.TempDir()
		xhttpDebugLogPath = filepath.Join(dir, "pup_xhttp_debug.log")
	})
	f, err := os.OpenFile(xhttpDebugLogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "%s %s\n", time.Now().Format("15:04:05.000"), fmt.Sprintf(format, args...))
}
