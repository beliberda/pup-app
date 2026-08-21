// Package olcrtc wraps the embeddable olcrtc client (github.com/openlibrecommunity/olcrtc)
// as a sing-box outbound. olcrtc has no dial-per-destination API: it starts its own
// loopback SOCKS5 listener and blocks until the tunnel dies, so this outbound starts
// the client once in Start and forwards DialContext to that local listener, the same
// shape used by protocol/tor for bine/tor and protocol/hiddify/dnstt for mahsanet/dnstt.
package olcrtc

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net"
	"os"
	"strings"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/protocol/socks"

	olcrtcclient "github.com/openlibrecommunity/olcrtc/pkg/olcrtc/client"
)

// startTimeout bounds how long Start waits for the WebRTC/SFU handshake and
// room join to complete before giving up.
const startTimeout = 30 * time.Second

func RegisterOutbound(registry *outbound.Registry) {
	outbound.Register[option.OlcrtcOutboundOptions](registry, C.TypeOlcrtc, NewOutbound)
}

var _ adapter.Outbound = (*Outbound)(nil)

type Outbound struct {
	outbound.Adapter
	ctx    context.Context
	logger logger.ContextLogger

	client    *olcrtcclient.Client
	socksUser string
	socksPass string

	cancel      context.CancelFunc
	done        chan struct{}
	socksClient *socks.Client
}

func NewOutbound(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options option.OlcrtcOutboundOptions) (adapter.Outbound, error) {
	cfg, socksUser, socksPass, err := buildClientConfig(options)
	if err != nil {
		return nil, E.Cause(err, "olcrtc: invalid options")
	}
	return &Outbound{
		Adapter:   outbound.NewAdapterWithDialerOptions(C.TypeOlcrtc, tag, []string{N.NetworkTCP}, options.DialerOptions),
		ctx:       ctx,
		logger:    logger,
		client:    olcrtcclient.New(cfg),
		socksUser: socksUser,
		socksPass: socksPass,
	}, nil
}

// Start joins the WebRTC room and waits for olcrtc's internal SOCKS5 listener
// to come up. Sing-box calls Start once, after all outbounds are constructed,
// before the router starts dialing through them.
func (o *Outbound) Start() error {
	runCtx, cancel := context.WithCancel(o.ctx)
	o.cancel = cancel
	done := make(chan struct{})
	o.done = done

	ready := make(chan string, 1)
	failed := make(chan error, 1)
	go func() {
		defer close(done)
		err := o.client.RunWithAddress(runCtx, func(addr string) {
			select {
			case ready <- addr:
			default:
			}
		})
		if err != nil {
			select {
			case failed <- err:
			default:
			}
		}
	}()

	select {
	case addr := <-ready:
		o.socksClient = socks.NewClient(N.SystemDialer, M.ParseSocksaddr(addr), socks.Version5, o.socksUser, o.socksPass)
		o.logger.Info("olcrtc tunnel ready, local socks5 at ", addr)
		return nil
	case err := <-failed:
		cancel()
		return E.Cause(err, "olcrtc: tunnel failed to start")
	case <-time.After(startTimeout):
		cancel()
		return E.New("olcrtc: timed out waiting for tunnel to become ready")
	}
}

func (o *Outbound) Close() error {
	if o.cancel != nil {
		o.cancel()
	}
	if o.done != nil {
		<-o.done
	}
	return nil
}

func (o *Outbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if o.socksClient == nil {
		return nil, E.New("olcrtc: outbound not started")
	}
	o.logger.InfoContext(ctx, "outbound connection to ", destination)
	return o.socksClient.DialContext(ctx, network, destination)
}

// ListenPacket is not supported: olcrtc is a TCP-over-WebRTC tunnel and its
// embedded SOCKS5 listener does not implement UDP ASSOCIATE.
func (o *Outbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, os.ErrInvalid
}

func buildClientConfig(options option.OlcrtcOutboundOptions) (olcrtcclient.Config, string, string, error) {
	if options.RoomID == "" {
		return olcrtcclient.Config{}, "", "", E.New("room_id is required")
	}

	keyHex := strings.TrimSpace(options.Key)
	if options.KeyFile != "" {
		data, err := os.ReadFile(options.KeyFile)
		if err != nil {
			return olcrtcclient.Config{}, "", "", E.Cause(err, "read key_file")
		}
		keyHex = strings.TrimSpace(string(data))
	}
	if keyHex == "" {
		return olcrtcclient.Config{}, "", "", E.New("key or key_file is required")
	}

	socksUser, err := randomHex(8)
	if err != nil {
		return olcrtcclient.Config{}, "", "", E.Cause(err, "generate local socks credentials")
	}
	socksPass, err := randomHex(8)
	if err != nil {
		return olcrtcclient.Config{}, "", "", E.Cause(err, "generate local socks credentials")
	}

	transport := options.Transport
	if transport == "" {
		transport = "datachannel"
	}

	liveness := olcrtcclient.LivenessConfig{
		Interval: 10 * time.Second,
		Timeout:  15 * time.Second,
		Failures: 4,
	}
	if options.Liveness != nil {
		liveness.Interval = durationOr(options.Liveness.Interval.Build(), liveness.Interval)
		liveness.Timeout = durationOr(options.Liveness.Timeout.Build(), liveness.Timeout)
		liveness.Failures = intOr(options.Liveness.Failures, liveness.Failures)
	}

	cfg := olcrtcclient.Config{
		Transport:     transport,
		Provider:      options.Provider,
		RoomURL:       options.RoomID,
		ChannelID:     options.ChannelID,
		ProviderToken: options.Token,
		KeyHex:        keyHex,
		// Bind on loopback only, on an OS-assigned port: this listener is
		// internal plumbing between this outbound and olcrtc's own tunnel,
		// never a user-facing proxy port, so it must not be predictable or
		// reachable from anything but this process (see CLAUDE.md 5.4).
		LocalAddr: "127.0.0.1:0",
		SOCKSUser: socksUser,
		SOCKSPass: socksPass,
		DNSServer: options.DNSServer,
		Liveness:  liveness,
	}
	if options.Traffic != nil {
		cfg.Traffic = olcrtcclient.TrafficConfig{
			MaxPayloadSize: options.Traffic.MaxPayloadSize,
			MinDelay:       options.Traffic.MinDelay.Build(),
			MaxDelay:       options.Traffic.MaxDelay.Build(),
		}
	}

	transportOptions, err := buildTransportOptions(transport, options)
	if err != nil {
		return olcrtcclient.Config{}, "", "", err
	}
	cfg.TransportOptions = transportOptions

	return cfg, socksUser, socksPass, nil
}

func buildTransportOptions(transport string, options option.OlcrtcOutboundOptions) (olcrtcclient.TransportOptions, error) {
	switch transport {
	case "vp8channel":
		vp8 := options.VP8
		if vp8 == nil {
			vp8 = &option.OlcrtcVP8Options{}
		}
		return olcrtcclient.VP8Options{
			FPS:       intOr(vp8.FPS, 30),
			BatchSize: intOr(vp8.BatchSize, 64),
		}, nil
	case "seichannel":
		sei := options.SEI
		if sei == nil {
			sei = &option.OlcrtcSEIOptions{}
		}
		return olcrtcclient.SEIOptions{
			FPS:          intOr(sei.FPS, 30),
			BatchSize:    intOr(sei.BatchSize, 64),
			FragmentSize: intOr(sei.FragmentSize, 900),
			AckTimeoutMS: intOr(sei.AckTimeoutMS, 2000),
		}, nil
	case "videochannel":
		video := options.Video
		if video == nil {
			video = &option.OlcrtcVideoOptions{}
		}
		codec := video.Codec
		if codec == "" {
			codec = "qrcode"
		}
		recovery := video.QRRecovery
		if recovery == "" {
			recovery = "low"
		}
		return olcrtcclient.VideoOptions{
			Width:      intOr(video.Width, 1920),
			Height:     intOr(video.Height, 1080),
			FPS:        intOr(video.FPS, 30),
			Codec:      codec,
			QRSize:     video.QRSize,
			QRRecovery: recovery,
			TileModule: intOr(video.TileModule, 4),
			TileRS:     intOr(video.TileRS, 20),
		}, nil
	case "datachannel", "":
		return nil, nil
	default:
		return nil, E.New("unknown transport: ", transport)
	}
}

func intOr(value, fallback int) int {
	if value == 0 {
		return fallback
	}
	return value
}

func durationOr(value, fallback time.Duration) time.Duration {
	if value == 0 {
		return fallback
	}
	return value
}

func randomHex(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
