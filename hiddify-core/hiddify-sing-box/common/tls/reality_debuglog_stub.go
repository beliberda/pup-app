//go:build with_utls && !hiddify_netdebug

package tls

func realityDebugLog(format string, args ...any) {}
