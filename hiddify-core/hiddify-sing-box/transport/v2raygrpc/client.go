package v2raygrpc

import (
	"context"
	"net"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/tls"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"

	"golang.org/x/net/http2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/backoff"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/keepalive"
)

// grpcServiceNameSegment mirrors Xray-core's Config.getServiceName()
// (transport/internet/grpc/config.go): the configured service_name is not
// used verbatim as the gRPC path segment. When it doesn't start with "/",
// Xray-core registers the service under url.PathEscape(serviceName) --
// notably percent-encoding any literal "/" the operator put in the name for
// obfuscation (e.g. "ci/cd-production-env" -> "ci%2Fcd-production-env") so it
// stays a single path segment. Without this, a raw serviceName containing a
// "/" makes our client's "/name/Tun" path have an extra segment, and the
// server reports "unknown service <name>" even though every credential is
// correct. The leading-"/" branch covers Xray-core's "custom path" mode,
// where the string is a real multi-segment path with each segment escaped
// individually.
func grpcServiceNameSegment(serviceName string) string {
	if !strings.HasPrefix(serviceName, "/") {
		return url.PathEscape(serviceName)
	}
	lastIndex := strings.LastIndex(serviceName, "/")
	if lastIndex < 1 {
		lastIndex = 1
	}
	parts := strings.Split(serviceName[1:lastIndex], "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return strings.Join(parts, "/")
}

var _ adapter.V2RayClientTransport = (*Client)(nil)

type Client struct {
	ctx         context.Context
	dialer      N.Dialer
	serverAddr  string
	serviceName string
	dialOptions []grpc.DialOption
	conn        atomic.Pointer[grpc.ClientConn]
	connAccess  sync.Mutex
}

func NewClient(ctx context.Context, dialer N.Dialer, serverAddr M.Socksaddr, options option.V2RayGRPCOptions, tlsConfig tls.Config) (adapter.V2RayClientTransport, error) {
	var dialOptions []grpc.DialOption
	if tlsConfig != nil {
		if len(tlsConfig.NextProtos()) == 0 {
			tlsConfig.SetNextProtos([]string{http2.NextProtoTLS})
		}
		dialOptions = append(dialOptions, grpc.WithTransportCredentials(NewTLSTransportCredentials(tlsConfig)))
	} else {
		dialOptions = append(dialOptions, grpc.WithTransportCredentials(insecure.NewCredentials()))
	}
	if options.IdleTimeout > 0 {
		dialOptions = append(dialOptions, grpc.WithKeepaliveParams(keepalive.ClientParameters{
			Time:                time.Duration(options.IdleTimeout),
			Timeout:             time.Duration(options.PingTimeout),
			PermitWithoutStream: options.PermitWithoutStream,
		}))
	}
	dialOptions = append(dialOptions, grpc.WithConnectParams(grpc.ConnectParams{
		Backoff: backoff.Config{
			BaseDelay:  500 * time.Millisecond,
			Multiplier: 1.5,
			Jitter:     0.2,
			MaxDelay:   19 * time.Second,
		},
		MinConnectTimeout: 5 * time.Second,
	}))
	dialOptions = append(dialOptions, grpc.WithContextDialer(func(ctx context.Context, server string) (net.Conn, error) {
		return dialer.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr(server))
	}))
	//nolint:staticcheck
	dialOptions = append(dialOptions, grpc.WithReturnConnectionError())
	return &Client{
		ctx:         ctx,
		dialer:      dialer,
		serverAddr:  serverAddr.String(),
		serviceName: options.ServiceName,
		dialOptions: dialOptions,
	}, nil
}

func (c *Client) connect() (*grpc.ClientConn, error) {
	conn := c.conn.Load()
	if conn != nil && conn.GetState() != connectivity.Shutdown {
		return conn, nil
	}
	c.connAccess.Lock()
	defer c.connAccess.Unlock()
	conn = c.conn.Load()
	if conn != nil && conn.GetState() != connectivity.Shutdown {
		return conn, nil
	}
	//nolint:staticcheck
	conn, err := grpc.DialContext(c.ctx, c.serverAddr, c.dialOptions...)
	if err != nil {
		return nil, err
	}
	c.conn.Store(conn)
	return conn, nil
}

func (c *Client) DialContext(ctx context.Context) (net.Conn, error) {
	clientConn, err := c.connect()
	if err != nil {
		return nil, err
	}
	client := NewGunServiceClient(clientConn).(GunServiceCustomNameClient)
	ctx, cancel := common.ContextWithCancelCause(ctx)
	stream, err := client.TunCustomName(ctx, grpcServiceNameSegment(c.serviceName))
	if err != nil {
		cancel(err)
		return nil, err
	}
	return NewGRPCConn(stream), nil
}

func (c *Client) Close() error {
	conn := c.conn.Swap(nil)
	if conn != nil {
		conn.Close()
	}
	return nil
}
