package ray2sing

import (
	"fmt"
	"strings"

	T "github.com/sagernet/sing-box/option"
)

// OlcrtcSingbox parses an olcrtc:// link as specified in
// github.com/openlibrecommunity/olcrtc docs/uri.md:
//
//	olcrtc://<Provider>?<Transport>@<RoomID>#<EncryptionKey>$<MIMO>
//	olcrtc://<Provider>?<Transport><key=value&key=value>@<RoomID>#<EncryptionKey>$<MIMO>
//
// This is not a standard URI (the '?', '@', '#', '$' separators do not carry
// their usual URI meaning, and RoomID for jitsi is itself a full URL), so it
// is parsed by hand rather than through net/url / ParseUrl.
func OlcrtcSingbox(link string) (*T.Outbound, error) {
	const prefix = "olcrtc://"
	if !strings.HasPrefix(link, prefix) {
		return nil, fmt.Errorf("olcrtc: missing %q prefix", prefix)
	}
	rest := link[len(prefix):]

	provider, rest, ok := cutOnce(rest, "?")
	if !ok {
		return nil, fmt.Errorf("olcrtc: missing '?' before transport")
	}
	if provider == "" {
		return nil, fmt.Errorf("olcrtc: empty provider")
	}

	transportBlock, rest, ok := cutOnce(rest, "@")
	if !ok {
		return nil, fmt.Errorf("olcrtc: missing '@' before room id")
	}
	transport, params := transportBlock, ""
	if i := strings.IndexByte(transportBlock, '<'); i >= 0 {
		if !strings.HasSuffix(transportBlock, ">") {
			return nil, fmt.Errorf("olcrtc: unterminated '<...>' transport payload")
		}
		transport = transportBlock[:i]
		params = transportBlock[i+1 : len(transportBlock)-1]
	}
	if transport == "" {
		return nil, fmt.Errorf("olcrtc: empty transport")
	}

	roomID, rest, ok := cutOnce(rest, "#")
	if !ok {
		return nil, fmt.Errorf("olcrtc: missing '#' before encryption key")
	}
	if roomID == "" {
		return nil, fmt.Errorf("olcrtc: empty room id")
	}

	key, mimo, _ := cutOnce(rest, "$")
	if key == "" {
		return nil, fmt.Errorf("olcrtc: empty encryption key")
	}

	paramMap := parseAngleParams(params)

	name := mimo
	if name == "" {
		name = "olcrtc-" + provider
	}

	options := &T.OlcrtcOutboundOptions{
		Provider:  provider,
		RoomID:    roomID,
		Key:       key,
		Transport: transport,
	}
	switch transport {
	case "vp8channel":
		options.VP8 = &T.OlcrtcVP8Options{
			FPS:       toInt(paramMap["vp8-fps"]),
			BatchSize: toInt(paramMap["vp8-batch"]),
		}
	case "seichannel":
		options.SEI = &T.OlcrtcSEIOptions{
			FPS:          toInt(paramMap["fps"]),
			BatchSize:    toInt(paramMap["batch"]),
			FragmentSize: toInt(paramMap["frag"]),
			AckTimeoutMS: toInt(paramMap["ack-ms"]),
		}
	case "videochannel":
		options.Video = &T.OlcrtcVideoOptions{
			Width:      toInt(paramMap["video-w"]),
			Height:     toInt(paramMap["video-h"]),
			FPS:        toInt(paramMap["video-fps"]),
			Codec:      paramMap["video-codec"],
			QRSize:     toInt(paramMap["video-qr-size"]),
			QRRecovery: paramMap["video-qr-recovery"],
			TileModule: toInt(paramMap["video-tile-module"]),
			TileRS:     toInt(paramMap["video-tile-rs"]),
		}
	}

	return &T.Outbound{
		Tag:     name + "§hide§",
		Type:    "olcrtc",
		Options: options,
	}, nil
}

// cutOnce splits s on the first occurrence of sep, mirroring strings.Cut.
func cutOnce(s, sep string) (before, after string, found bool) {
	if i := strings.Index(s, sep); i >= 0 {
		return s[:i], s[i+len(sep):], true
	}
	return s, "", false
}

// parseAngleParams parses a "key=value&key=value" transport payload block.
func parseAngleParams(raw string) map[string]string {
	result := make(map[string]string)
	if raw == "" {
		return result
	}
	for _, pair := range strings.Split(raw, "&") {
		if pair == "" {
			continue
		}
		k, v, _ := cutOnce(pair, "=")
		result[strings.ToLower(k)] = v
	}
	return result
}
