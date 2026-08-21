package option

import "github.com/sagernet/sing/common/json/badoption"

type OlcrtcOutboundOptions struct {
	DialerOptions
	Network NetworkList `json:"network,omitempty"`

	// Provider is the signaling/SFU provider: jitsi, telemost or wbstream.
	Provider string `json:"provider"`
	// RoomID is the room identifier or, for jitsi, the full room URL.
	RoomID string `json:"room_id"`
	// ChannelID is an optional peer-routing channel id.
	ChannelID string `json:"channel_id,omitempty"`
	// Token is an optional pre-issued provider account/moderator token
	// (required for wbstream + datachannel).
	Token string `json:"token,omitempty"`

	// Key is the 64-char hex OLC2 pre-shared key. Mutually exclusive with KeyFile.
	Key string `json:"key,omitempty"`
	// KeyFile is a path to a file holding the hex key.
	KeyFile string `json:"key_file,omitempty"`

	// Transport is one of datachannel, vp8channel, seichannel, videochannel.
	Transport string `json:"transport,omitempty"`
	// DNSServer overrides the resolver olcrtc itself uses for signaling lookups.
	DNSServer string `json:"dns_server,omitempty"`

	Liveness *OlcrtcLivenessOptions `json:"liveness,omitempty"`
	Traffic  *OlcrtcTrafficOptions  `json:"traffic,omitempty"`
	VP8      *OlcrtcVP8Options      `json:"vp8,omitempty"`
	SEI      *OlcrtcSEIOptions      `json:"sei,omitempty"`
	Video    *OlcrtcVideoOptions    `json:"video,omitempty"`
}

type OlcrtcLivenessOptions struct {
	Interval badoption.Duration `json:"interval,omitempty"`
	Timeout  badoption.Duration `json:"timeout,omitempty"`
	Failures int                `json:"failures,omitempty"`
}

type OlcrtcTrafficOptions struct {
	MaxPayloadSize int                `json:"max_payload_size,omitempty"`
	MinDelay       badoption.Duration `json:"min_delay,omitempty"`
	MaxDelay       badoption.Duration `json:"max_delay,omitempty"`
}

type OlcrtcVP8Options struct {
	FPS       int `json:"fps,omitempty"`
	BatchSize int `json:"batch_size,omitempty"`
}

type OlcrtcSEIOptions struct {
	FPS          int `json:"fps,omitempty"`
	BatchSize    int `json:"batch_size,omitempty"`
	FragmentSize int `json:"fragment_size,omitempty"`
	AckTimeoutMS int `json:"ack_timeout_ms,omitempty"`
}

type OlcrtcVideoOptions struct {
	Width      int    `json:"width,omitempty"`
	Height     int    `json:"height,omitempty"`
	FPS        int    `json:"fps,omitempty"`
	Codec      string `json:"codec,omitempty"`
	QRSize     int    `json:"qr_size,omitempty"`
	QRRecovery string `json:"qr_recovery,omitempty"`
	TileModule int    `json:"tile_module,omitempty"`
	TileRS     int    `json:"tile_rs,omitempty"`
}
