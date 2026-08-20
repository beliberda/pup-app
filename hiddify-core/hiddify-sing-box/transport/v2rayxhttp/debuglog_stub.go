//go:build !hiddify_netdebug

package xhttp

func xhttpDebugLog(format string, args ...any) {}
