package route

import (
	"context"
	"fmt"
	"net/netip"
	"sync"
	"syscall"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/process"
	N "github.com/sagernet/sing/common/network"
	"golang.org/x/sync/singleflight"
)

// Caching + in-flight dedup for the platform-backed (JNI/gomobile on
// Android, NetworkExtension on iOS/macOS) connection-owner lookup.
//
// Without this, every new flow independently hits the cross-language
// bridge twice (once from the TUN inbound's pre-match, once from the
// actual route match for the same 5-tuple), and short-lived UDP flows
// (apps that open many small sockets in bursts) can fire many of these
// concurrently. On Android that bursty concurrency has been observed to
// crash the process with `Abort message: 'Unknown reference: N'` inside
// the vendored gomobile v0.1.11 Java ref-tracker bridge. Caching by
// 5-tuple with a short TTL, plus singleflight to collapse concurrent
// misses for the same flow into one real call, cuts both the call volume
// and the concurrency hitting that bridge.
const (
	connectionOwnerCacheTTL        = 30 * time.Second
	connectionOwnerErrCacheTTL     = 5 * time.Second
	connectionOwnerCacheMaxEntries = 4096
)

type ownerCacheKey struct {
	network     string
	source      netip.AddrPort
	destination netip.AddrPort
}

type ownerCacheEntry struct {
	owner     *adapter.ConnectionOwner
	err       error
	expiresAt time.Time
}

type platformSearcher struct {
	platform adapter.PlatformInterface

	group singleflight.Group

	mu    sync.Mutex
	cache map[ownerCacheKey]ownerCacheEntry
}

func newPlatformSearcher(platform adapter.PlatformInterface) process.Searcher {
	return &platformSearcher{
		platform: platform,
		cache:    make(map[ownerCacheKey]ownerCacheEntry),
	}
}

func (s *platformSearcher) FindProcessInfo(ctx context.Context, network string, source netip.AddrPort, destination netip.AddrPort) (*adapter.ConnectionOwner, error) {
	if !s.platform.UsePlatformConnectionOwnerFinder() {
		return nil, process.ErrNotFound
	}

	var ipProtocol int32
	switch N.NetworkName(network) {
	case N.NetworkTCP:
		ipProtocol = syscall.IPPROTO_TCP
	case N.NetworkUDP:
		ipProtocol = syscall.IPPROTO_UDP
	default:
		return nil, process.ErrNotFound
	}

	key := ownerCacheKey{network: network, source: source, destination: destination}

	if owner, err, ok := s.load(key); ok {
		return owner, err
	}

	groupKey := fmt.Sprintf("%s|%s|%s", network, source, destination)
	v, err, _ := s.group.Do(groupKey, func() (interface{}, error) {
		// Another goroutine may have populated the cache while this one
		// was waiting to enter singleflight for the same key.
		if owner, cErr, ok := s.load(key); ok {
			return owner, cErr
		}
		request := &adapter.FindConnectionOwnerRequest{
			IpProtocol:         ipProtocol,
			SourceAddress:      source.Addr().String(),
			SourcePort:         int32(source.Port()),
			DestinationAddress: destination.Addr().String(),
			DestinationPort:    int32(destination.Port()),
		}
		owner, fErr := s.platform.FindConnectionOwner(request)
		s.store(key, owner, fErr)
		return owner, fErr
	})
	if v == nil {
		return nil, err
	}
	return v.(*adapter.ConnectionOwner), err
}

func (s *platformSearcher) load(key ownerCacheKey) (*adapter.ConnectionOwner, error, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.cache[key]
	if !ok || time.Now().After(entry.expiresAt) {
		return nil, nil, false
	}
	return entry.owner, entry.err, true
}

func (s *platformSearcher) store(key ownerCacheKey, owner *adapter.ConnectionOwner, err error) {
	ttl := connectionOwnerCacheTTL
	if err != nil {
		ttl = connectionOwnerErrCacheTTL
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.cache) >= connectionOwnerCacheMaxEntries {
		s.sweepLocked()
		if len(s.cache) >= connectionOwnerCacheMaxEntries {
			s.cache = make(map[ownerCacheKey]ownerCacheEntry)
		}
	}
	s.cache[key] = ownerCacheEntry{owner: owner, err: err, expiresAt: time.Now().Add(ttl)}
}

func (s *platformSearcher) sweepLocked() {
	now := time.Now()
	for k, v := range s.cache {
		if now.After(v.expiresAt) {
			delete(s.cache, k)
		}
	}
}
