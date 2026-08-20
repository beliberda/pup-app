//go:build with_utls && hiddify_netdebug

package tls

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// realityDebugLog is diagnostic instrumentation for the Reality handshake:
// the generic sing-box connection wrapper only reports "closed pipe" for
// every kind of downstream failure once the Reality handshake gives up,
// discarding whether the peer certificate looked like the server's crafted
// reality cert (ed25519, HMAC-signed with the derived auth key) or a real
// CA-issued cert (meaning the server never recognized this client's auth and
// fell back to proxying the camouflage domain for real). Only compiled in
// with the hiddify_netdebug build tag -- release builds get the no-op in
// reality_debuglog_stub.go instead.
var realityDebugLogOnce sync.Once
var realityDebugLogPath string

func realityDebugLog(format string, args ...any) {
	realityDebugLogOnce.Do(func() {
		dir := os.TempDir()
		realityDebugLogPath = filepath.Join(dir, "pup_reality_debug.log")
	})
	f, err := os.OpenFile(realityDebugLogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "%s %s\n", time.Now().Format("15:04:05.000"), fmt.Sprintf(format, args...))
}
