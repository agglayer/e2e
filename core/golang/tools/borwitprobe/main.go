package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"hash/crc32"
	"math/big"
	"net"
	"os"
	"slices"
	"strconv"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/forkid"
	"github.com/ethereum/go-ethereum/crypto"
	ethproto "github.com/ethereum/go-ethereum/eth/protocols/eth"
	"github.com/ethereum/go-ethereum/p2p"
	"github.com/ethereum/go-ethereum/p2p/enode"
	"github.com/ethereum/go-ethereum/p2p/rlpx"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/ethereum/go-ethereum/rpc"
)

const (
	baseProtocolVersion = 5
	baseProtocolLength  = uint64(16)
	ethProtocolLength   = uint64(18)

	handshakeMsg = 0x00
	discMsg      = 0x01
	pingMsg      = 0x02
	pongMsg      = 0x03

	ethVersion69 = uint(69)
	ethVersion68 = uint(68)

	witVersion2 = uint(2)
	witVersion1 = uint(1)

	getWitnessMsg         = uint64(0x02)
	witnessMsg            = uint64(0x03)
	getWitnessMetadataMsg = uint64(0x04)
	witnessMetadataMsg    = uint64(0x05)

	defaultTimeout = 10 * time.Second
)

type probeMode string

const (
	modeProbe              probeMode = "probe"
	modeStatusOnly         probeMode = "status-only"
	modeGetWitness         probeMode = "get-witness"
	modeGetWitnessMetadata probeMode = "get-witness-metadata"
)

type protoHandshake struct {
	Version    uint64
	Name       string
	Caps       []p2p.Cap
	ListenPort uint64
	ID         []byte
	Rest       []rlp.RawValue `rlp:"tail"`
}

type rpcBlock struct {
	Hash            common.Hash    `json:"hash"`
	Number          hexutil.Uint64 `json:"number"`
	Timestamp       hexutil.Uint64 `json:"timestamp"`
	TotalDifficulty *hexutil.Big   `json:"totalDifficulty"`
}

type genesisDocument struct {
	Config *chainConfig `json:"config"`
}

type chainConfig struct {
	HomesteadBlock      *big.Int   `json:"homesteadBlock,omitempty"`
	DAOForkBlock        *big.Int   `json:"daoForkBlock,omitempty"`
	EIP150Block         *big.Int   `json:"eip150Block,omitempty"`
	EIP155Block         *big.Int   `json:"eip155Block,omitempty"`
	EIP158Block         *big.Int   `json:"eip158Block,omitempty"`
	ByzantiumBlock      *big.Int   `json:"byzantiumBlock,omitempty"`
	ConstantinopleBlock *big.Int   `json:"constantinopleBlock,omitempty"`
	PetersburgBlock     *big.Int   `json:"petersburgBlock,omitempty"`
	IstanbulBlock       *big.Int   `json:"istanbulBlock,omitempty"`
	MuirGlacierBlock    *big.Int   `json:"muirGlacierBlock,omitempty"`
	BerlinBlock         *big.Int   `json:"berlinBlock,omitempty"`
	LondonBlock         *big.Int   `json:"londonBlock,omitempty"`
	ArrowGlacierBlock   *big.Int   `json:"arrowGlacierBlock,omitempty"`
	GrayGlacierBlock    *big.Int   `json:"grayGlacierBlock,omitempty"`
	MergeNetsplitBlock  *big.Int   `json:"mergeNetsplitBlock,omitempty"`
	ShanghaiBlock       *big.Int   `json:"shanghaiBlock,omitempty"`
	CancunBlock         *big.Int   `json:"cancunBlock,omitempty"`
	PragueBlock         *big.Int   `json:"pragueBlock,omitempty"`
	VerkleBlock         *big.Int   `json:"verkleBlock,omitempty"`
	ShanghaiTime        *uint64    `json:"shanghaiTime,omitempty"`
	CancunTime          *uint64    `json:"cancunTime,omitempty"`
	PragueTime          *uint64    `json:"pragueTime,omitempty"`
	VerkleTime          *uint64    `json:"verkleTime,omitempty"`
	Bor                 *borConfig `json:"bor,omitempty"`
}

type borConfig struct {
	JaipurBlock       *big.Int `json:"jaipurBlock,omitempty"`
	DelhiBlock        *big.Int `json:"delhiBlock,omitempty"`
	IndoreBlock       *big.Int `json:"indoreBlock,omitempty"`
	AhmedabadBlock    *big.Int `json:"ahmedabadBlock,omitempty"`
	BhilaiBlock       *big.Int `json:"bhilaiBlock,omitempty"`
	RioBlock          *big.Int `json:"rioBlock,omitempty"`
	MadhugiriBlock    *big.Int `json:"madhugiriBlock,omitempty"`
	MadhugiriProBlock *big.Int `json:"madhugiriProBlock,omitempty"`
	DandeliBlock      *big.Int `json:"dandeliBlock,omitempty"`
	LisovoBlock       *big.Int `json:"lisovoBlock,omitempty"`
	LisovoProBlock    *big.Int `json:"lisovoProBlock,omitempty"`
	GiuglianoBlock    *big.Int `json:"giuglianoBlock,omitempty"`
}

type statusInfo struct {
	networkID  uint64
	td         *big.Int
	genesis    common.Hash
	forkID     forkid.ID
	latestNum  uint64
	latestHash common.Hash
}

type statusPacket68 struct {
	ProtocolVersion uint32
	NetworkID       uint64
	TD              *big.Int
	Head            common.Hash
	Genesis         common.Hash
	ForkID          forkid.ID
}

type statusPacket69 struct {
	ProtocolVersion uint32
	NetworkID       uint64
	TD              *big.Int
	Genesis         common.Hash
	ForkID          forkid.ID
	EarliestBlock   uint64
	LatestBlock     uint64
	LatestBlockHash common.Hash
}

type WitnessPageRequest struct {
	Hash common.Hash
	Page uint64
}

type GetWitnessRequest struct {
	WitnessPages []WitnessPageRequest
}

type GetWitnessPacket struct {
	RequestId uint64
	*GetWitnessRequest
}

type WitnessPageResponse struct {
	Data       []byte
	Hash       common.Hash
	Page       uint64
	TotalPages uint64
}

type WitnessPacketResponse []WitnessPageResponse

type WitnessPacketRLPPacket struct {
	RequestId uint64
	WitnessPacketResponse
}

type GetWitnessMetadataRequest struct {
	Hashes []common.Hash
}

type GetWitnessMetadataPacket struct {
	RequestId uint64
	*GetWitnessMetadataRequest
}

type WitnessMetadataResponse struct {
	Hash        common.Hash
	TotalPages  uint64
	WitnessSize uint64
	BlockNumber uint64
	Available   bool
}

type WitnessMetadataPacket struct {
	RequestId uint64
	Metadata  []WitnessMetadataResponse
}

type result struct {
	Outcome       string   `json:"outcome"`
	Error         string   `json:"error,omitempty"`
	DiscReason    string   `json:"disc_reason,omitempty"`
	ObservedCodes []uint64 `json:"observed_codes,omitempty"`
	RemoteCaps    []string `json:"remote_caps,omitempty"`
	LocalID       string   `json:"local_id,omitempty"`
	LocalForkID   string   `json:"local_fork_id,omitempty"`
	RemoteForkID  string   `json:"remote_fork_id,omitempty"`
	LocalGenesis  string   `json:"local_genesis,omitempty"`
	RemoteGenesis string   `json:"remote_genesis,omitempty"`
	LocalNetwork  uint64   `json:"local_network,omitempty"`
	RemoteNetwork uint64   `json:"remote_network,omitempty"`
	NegotiatedEth uint     `json:"negotiated_eth,omitempty"`
	NegotiatedWit uint     `json:"negotiated_wit,omitempty"`
	RequestCount  int      `json:"request_count,omitempty"`
	ResponseCount int      `json:"response_count,omitempty"`
	RequestBytes  int      `json:"request_payload_bytes,omitempty"`
	ResponseBytes int      `json:"response_payload_bytes,omitempty"`
	RoundTripMS   int64    `json:"round_trip_ms,omitempty"`
	RequestHash   string   `json:"request_hash,omitempty"`
}

type remoteStatusView struct {
	networkID uint64
	genesis   common.Hash
	forkID    forkid.ID
}

type session struct {
	conn   *rlpx.Conn
	ourKey *ecdsa.PrivateKey
}

type flags struct {
	mode         probeMode
	enode        string
	rpcURL       string
	genesisPath  string
	timeout      time.Duration
	count        int
	hash         common.Hash
	uniqueHashes bool
	ethVersion   uint
	witOffset    uint64
}

func main() {
	cfg, err := parseFlags()
	if err != nil {
		writeAndExit(result{Outcome: "setup_error", Error: err.Error()}, 1)
	}
	res, code := run(cfg)
	writeAndExit(res, code)
}

func parseFlags() (*flags, error) {
	mode := flag.String("mode", string(modeProbe), "probe|status-only|get-witness|get-witness-metadata")
	enodeStr := flag.String("enode", "", "target enode URL")
	rpcURL := flag.String("rpc-url", "", "JSON-RPC URL for status exchange")
	genesisPath := flag.String("genesis", "", "path to genesis.json")
	timeout := flag.Duration("timeout", defaultTimeout, "overall timeout")
	count := flag.Int("count", 1, "number of witness pages or hashes to request")
	hashHex := flag.String("hash", common.Hash{}.Hex(), "block hash to request")
	unique := flag.Bool("unique", false, "generate unique hashes/pages instead of repeating one hash")
	ethVersion := flag.Uint("eth-version", ethVersion68, "eth protocol version to advertise/use (68 or 69; default 68 because Bor 2.7.x disconnects this helper after eth/69 status exchange)")
	witOffset := flag.Uint64("wit-offset", 0, "override the negotiated global wire offset for wit messages (0 = auto)")
	flag.Parse()

	if *enodeStr == "" {
		return nil, errors.New("missing --enode")
	}
	if *count < 1 {
		return nil, errors.New("--count must be >= 1")
	}
	h := common.HexToHash(*hashHex)

	cfg := &flags{
		mode:         probeMode(*mode),
		enode:        *enodeStr,
		rpcURL:       *rpcURL,
		genesisPath:  *genesisPath,
		timeout:      *timeout,
		count:        *count,
		hash:         h,
		uniqueHashes: *unique,
		ethVersion:   *ethVersion,
		witOffset:    *witOffset,
	}
	if cfg.ethVersion != ethVersion68 && cfg.ethVersion != ethVersion69 {
		return nil, fmt.Errorf("unsupported --eth-version %d (use 68 or 69)", cfg.ethVersion)
	}
	switch cfg.mode {
	case modeProbe:
		return cfg, nil
	case modeStatusOnly:
		return cfg, nil
	case modeGetWitness, modeGetWitnessMetadata:
		if cfg.rpcURL == "" {
			return nil, errors.New("missing --rpc-url")
		}
		if cfg.genesisPath == "" {
			return nil, errors.New("missing --genesis")
		}
		return cfg, nil
	default:
		return nil, fmt.Errorf("unsupported --mode %q", cfg.mode)
	}
}

func run(cfg *flags) (result, int) {
	ctx, cancel := context.WithTimeout(context.Background(), cfg.timeout)
	defer cancel()

	sess, remoteHello, err := dialAndHello(ctx, cfg.enode, cfg.ethVersion)
	if err != nil {
		return result{Outcome: "hello_error", Error: err.Error()}, 0
	}
	defer sess.conn.Close()

	remoteCaps := capsToStrings(remoteHello.Caps)
	negEth := negotiateVersion(remoteHello.Caps, "eth", []uint{cfg.ethVersion})
	negWit := negotiateVersion(remoteHello.Caps, "wit", []uint{witVersion2, witVersion1})

	out := result{
		RemoteCaps:    remoteCaps,
		LocalID:       enode.PubkeyToIDV4(&sess.ourKey.PublicKey).String(),
		NegotiatedEth: negEth,
		NegotiatedWit: negWit,
		RequestCount:  cfg.count,
		RequestHash:   cfg.hash.Hex(),
	}
	if negWit == 0 {
		out.Outcome = "no_wit_cap"
		return out, 0
	}
	if cfg.mode == modeProbe {
		out.Outcome = "probe_ok"
		return out, 0
	}
	if negEth == 0 {
		out.Outcome = "no_eth_cap"
		return out, 0
	}
	if cfg.mode == modeGetWitnessMetadata && negWit < witVersion2 {
		out.Outcome = "no_wit_metadata_cap"
		return out, 0
	}

	status, err := fetchStatusInfo(ctx, cfg.rpcURL, cfg.genesisPath)
	if err != nil {
		out.Outcome = "status_setup_error"
		out.Error = err.Error()
		return out, 1
	}
	out.LocalForkID = fmt.Sprintf("%#x/%#x", status.forkID.Hash[:4], status.forkID.Next)
	out.LocalGenesis = status.genesis.Hex()
	out.LocalNetwork = status.networkID
	remoteStatus, err := exchangeStatus(ctx, sess.conn, negEth, status)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			out.Outcome = "timeout"
			out.Error = err.Error()
			out.DiscReason = disconnectReason(err)
			return out, 0
		}
		out.Outcome = classifyPeerError(err)
		out.Error = err.Error()
		out.DiscReason = disconnectReason(err)
		return out, 0
	}
	if remoteStatus != nil {
		out.RemoteForkID = fmt.Sprintf("%#x/%#x", remoteStatus.forkID.Hash[:4], remoteStatus.forkID.Next)
		out.RemoteGenesis = remoteStatus.genesis.Hex()
		out.RemoteNetwork = remoteStatus.networkID
	}
	if cfg.mode == modeStatusOnly {
		postStatusCtx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		code, data, err := readFrame(postStatusCtx, sess.conn)
		switch {
		case err == nil:
			out.ObservedCodes = append(out.ObservedCodes, code)
			if code == discMsg {
				out.Outcome = "disconnect"
				err = decodeDisconnect(data, "after status exchange")
				out.Error = err.Error()
				out.DiscReason = disconnectReason(err)
				return out, 0
			}
			out.Outcome = "status_ok"
			return out, 0
		case errors.Is(err, context.DeadlineExceeded):
			out.Outcome = "status_ok"
			return out, 0
		default:
			out.Outcome = classifyPeerError(err)
			out.Error = err.Error()
			out.DiscReason = disconnectReason(err)
			return out, 0
		}
	}

	switch cfg.mode {
	case modeGetWitness:
		req := &GetWitnessPacket{
			RequestId: 1,
			GetWitnessRequest: &GetWitnessRequest{
				WitnessPages: buildWitnessPages(cfg.hash, cfg.count, cfg.uniqueHashes),
			},
		}
		witBase := negotiatedWitOffset(cfg, negEth)
		payload, err := encodeRLP(req)
		if err != nil {
			out.Outcome = "write_error"
			out.Error = err.Error()
			return out, 1
		}
		out.RequestBytes = len(payload)
		start := time.Now()
		if err := writePayload(ctx, sess.conn, witBase+getWitnessMsg, payload); err != nil {
			out.Outcome = "write_error"
			out.Error = err.Error()
			return out, 1
		}
		resp, responseBytes, err := readWitnessResponse(ctx, sess.conn, witBase+witnessMsg, &out.ObservedCodes)
		out.RoundTripMS = time.Since(start).Milliseconds()
		if err != nil {
			out.Outcome = classifyPeerError(err)
			out.Error = err.Error()
			out.DiscReason = disconnectReason(err)
			return out, 0
		}
		out.Outcome = "response"
		out.ResponseCount = len(resp.WitnessPacketResponse)
		out.ResponseBytes = responseBytes
		return out, 0
	case modeGetWitnessMetadata:
		req := &GetWitnessMetadataPacket{
			RequestId: 1,
			GetWitnessMetadataRequest: &GetWitnessMetadataRequest{
				Hashes: buildHashes(cfg.hash, cfg.count, cfg.uniqueHashes),
			},
		}
		witBase := negotiatedWitOffset(cfg, negEth)
		payload, err := encodeRLP(req)
		if err != nil {
			out.Outcome = "write_error"
			out.Error = err.Error()
			return out, 1
		}
		out.RequestBytes = len(payload)
		start := time.Now()
		if err := writePayload(ctx, sess.conn, witBase+getWitnessMetadataMsg, payload); err != nil {
			out.Outcome = "write_error"
			out.Error = err.Error()
			return out, 1
		}
		resp, responseBytes, err := readWitnessMetadataResponse(ctx, sess.conn, witBase+witnessMetadataMsg, &out.ObservedCodes)
		out.RoundTripMS = time.Since(start).Milliseconds()
		if err != nil {
			out.Outcome = classifyPeerError(err)
			out.Error = err.Error()
			out.DiscReason = disconnectReason(err)
			return out, 0
		}
		out.Outcome = "response"
		out.ResponseCount = len(resp.Metadata)
		out.ResponseBytes = responseBytes
		return out, 0
	default:
		out.Outcome = "setup_error"
		out.Error = "unreachable mode"
		return out, 1
	}
}

func dialAndHello(ctx context.Context, rawEnode string, ethVersion uint) (*session, *protoHandshake, error) {
	node, err := enode.Parse(enode.ValidSchemes, rawEnode)
	if err != nil {
		return nil, nil, fmt.Errorf("parse enode: %w", err)
	}
	tcpEndpoint, ok := node.TCPEndpoint()
	if !ok {
		return nil, nil, errors.New("enode has no TCP endpoint")
	}
	dialer := net.Dialer{Timeout: remainingOr(ctx, 5*time.Second)}
	fd, err := dialer.DialContext(ctx, "tcp", tcpEndpoint.String())
	if err != nil {
		return nil, nil, fmt.Errorf("dial tcp: %w", err)
	}
	key, err := crypto.GenerateKey()
	if err != nil {
		fd.Close()
		return nil, nil, fmt.Errorf("generate key: %w", err)
	}
	conn := rlpx.NewConn(fd, node.Pubkey())
	if _, err := conn.Handshake(key); err != nil {
		conn.Close()
		return nil, nil, fmt.Errorf("rlpx handshake: %w", err)
	}
	sess := &session{conn: conn, ourKey: key}
	hello := &protoHandshake{
		Version: baseProtocolVersion,
		Name:    "borwitprobe",
		Caps:    helloCaps(ethVersion),
		ID:      crypto.FromECDSAPub(&key.PublicKey)[1:],
	}
	if err := writeRLP(ctx, conn, handshakeMsg, hello); err != nil {
		conn.Close()
		return nil, nil, fmt.Errorf("write hello: %w", err)
	}
	remoteHello, err := readHello(ctx, conn)
	if err != nil {
		conn.Close()
		return nil, nil, err
	}
	if remoteHello.Version >= baseProtocolVersion {
		conn.SetSnappy(true)
	}
	return sess, remoteHello, nil
}

func fetchStatusInfo(ctx context.Context, rpcURL, genesisPath string) (*statusInfo, error) {
	clt, err := rpc.DialContext(ctx, rpcURL)
	if err != nil {
		return nil, fmt.Errorf("dial rpc: %w", err)
	}
	defer clt.Close()

	var latest rpcBlock
	if err := clt.CallContext(ctx, &latest, "eth_getBlockByNumber", "latest", false); err != nil {
		return nil, fmt.Errorf("fetch latest block: %w", err)
	}
	var genesisBlock rpcBlock
	if err := clt.CallContext(ctx, &genesisBlock, "eth_getBlockByNumber", "0x0", false); err != nil {
		return nil, fmt.Errorf("fetch genesis block: %w", err)
	}
	var networkRaw string
	if err := clt.CallContext(ctx, &networkRaw, "net_version"); err != nil {
		return nil, fmt.Errorf("fetch net_version: %w", err)
	}
	networkID, err := strconv.ParseUint(networkRaw, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("parse net_version %q: %w", networkRaw, err)
	}
	genesisJSON, err := os.ReadFile(genesisPath)
	if err != nil {
		return nil, fmt.Errorf("read genesis: %w", err)
	}
	var genesis genesisDocument
	if err := json.Unmarshal(genesisJSON, &genesis); err != nil {
		return nil, fmt.Errorf("decode genesis: %w", err)
	}
	if genesis.Config == nil {
		return nil, errors.New("genesis config missing")
	}
	fid := newForkID(genesisBlock.Hash, uint64(genesisBlock.Timestamp), genesis.Config, uint64(latest.Number), uint64(latest.Timestamp))
	td := big.NewInt(0)
	if latest.TotalDifficulty != nil {
		td = latest.TotalDifficulty.ToInt()
	} else {
		td = new(big.Int).SetUint64(uint64(latest.Number) + 1)
	}
	return &statusInfo{
		networkID:  networkID,
		td:         td,
		genesis:    genesisBlock.Hash,
		forkID:     fid,
		latestNum:  uint64(latest.Number),
		latestHash: latest.Hash,
	}, nil
}

func exchangeStatus(ctx context.Context, conn *rlpx.Conn, version uint, status *statusInfo) (*remoteStatusView, error) {
	var pkt any
	switch version {
	case ethVersion69:
		pkt = &statusPacket69{
			ProtocolVersion: uint32(version),
			NetworkID:       status.networkID,
			TD:              status.td,
			Genesis:         status.genesis,
			ForkID:          status.forkID,
			EarliestBlock:   0,
			LatestBlock:     status.latestNum,
			LatestBlockHash: status.latestHash,
		}
	default:
		pkt = &statusPacket68{
			ProtocolVersion: uint32(version),
			NetworkID:       status.networkID,
			TD:              status.td,
			Head:            status.latestHash,
			Genesis:         status.genesis,
			ForkID:          status.forkID,
		}
	}
	if err := writeRLP(ctx, conn, ethOffset()+ethproto.StatusMsg, pkt); err != nil {
		return nil, err
	}
	for {
		code, data, err := readFrame(ctx, conn)
		if err != nil {
			return nil, err
		}
		switch code {
		case discMsg:
			return nil, decodeDisconnect(data, "during status exchange")
		case pingMsg:
			if err := writePong(ctx, conn); err != nil {
				return nil, err
			}
		case ethOffset() + ethproto.StatusMsg:
			remote, err := decodeRemoteStatus(version, data)
			if err != nil {
				return nil, fmt.Errorf("decode remote status: %w", err)
			}
			return remote, nil
		}
	}
}

func decodeRemoteStatus(version uint, data []byte) (*remoteStatusView, error) {
	switch version {
	case ethVersion69:
		var resp statusPacket69
		if err := rlp.DecodeBytes(data, &resp); err != nil {
			return nil, err
		}
		return &remoteStatusView{
			networkID: resp.NetworkID,
			genesis:   resp.Genesis,
			forkID:    resp.ForkID,
		}, nil
	default:
		var resp statusPacket68
		if err := rlp.DecodeBytes(data, &resp); err != nil {
			return nil, err
		}
		return &remoteStatusView{
			networkID: resp.NetworkID,
			genesis:   resp.Genesis,
			forkID:    resp.ForkID,
		}, nil
	}
}

func readHello(ctx context.Context, conn *rlpx.Conn) (*protoHandshake, error) {
	for {
		code, data, err := readFrame(ctx, conn)
		if err != nil {
			return nil, err
		}
		switch code {
		case handshakeMsg:
			var hello protoHandshake
			if err := rlp.DecodeBytes(data, &hello); err != nil {
				return nil, fmt.Errorf("decode remote hello: %w", err)
			}
			return &hello, nil
		case discMsg:
			return nil, decodeDisconnect(data, "during hello")
		case pingMsg:
			if err := writePong(ctx, conn); err != nil {
				return nil, err
			}
		}
	}
}

func readWitnessResponse(ctx context.Context, conn *rlpx.Conn, expected uint64, observed *[]uint64) (*WitnessPacketRLPPacket, int, error) {
	for {
		code, data, err := readFrame(ctx, conn)
		if err != nil {
			return nil, 0, err
		}
		*observed = append(*observed, code)
		switch code {
		case discMsg:
			return nil, 0, decodeDisconnect(data, "")
		case pingMsg:
			if err := writePong(ctx, conn); err != nil {
				return nil, 0, err
			}
		case expected:
			var resp WitnessPacketRLPPacket
			if err := rlp.DecodeBytes(data, &resp); err != nil {
				return nil, 0, fmt.Errorf("decode witness response: %w", err)
			}
			return &resp, len(data), nil
		}
	}
}

func readWitnessMetadataResponse(ctx context.Context, conn *rlpx.Conn, expected uint64, observed *[]uint64) (*WitnessMetadataPacket, int, error) {
	for {
		code, data, err := readFrame(ctx, conn)
		if err != nil {
			return nil, 0, err
		}
		*observed = append(*observed, code)
		switch code {
		case discMsg:
			return nil, 0, decodeDisconnect(data, "")
		case pingMsg:
			if err := writePong(ctx, conn); err != nil {
				return nil, 0, err
			}
		case expected:
			var resp WitnessMetadataPacket
			if err := rlp.DecodeBytes(data, &resp); err != nil {
				return nil, 0, fmt.Errorf("decode witness metadata response: %w", err)
			}
			return &resp, len(data), nil
		}
	}
}

func buildWitnessPages(base common.Hash, count int, unique bool) []WitnessPageRequest {
	pages := make([]WitnessPageRequest, count)
	for i := 0; i < count; i++ {
		hash := base
		if unique {
			hash = deriveHash(base, i)
		}
		pages[i] = WitnessPageRequest{Hash: hash, Page: 0}
	}
	return pages
}

func buildHashes(base common.Hash, count int, unique bool) []common.Hash {
	hashes := make([]common.Hash, count)
	for i := 0; i < count; i++ {
		hashes[i] = base
		if unique {
			hashes[i] = deriveHash(base, i)
		}
	}
	return hashes
}

func deriveHash(base common.Hash, i int) common.Hash {
	buf := append(base[:0:0], base[:]...)
	big.NewInt(int64(i + 1)).FillBytes(buf)
	return common.BytesToHash(buf)
}

func readFrame(ctx context.Context, conn *rlpx.Conn) (uint64, []byte, error) {
	conn.SetReadDeadline(deadlineFrom(ctx))
	code, data, _, err := conn.Read()
	if err != nil {
		if ne, ok := err.(net.Error); ok && ne.Timeout() {
			if ctx.Err() != nil {
				return 0, nil, ctx.Err()
			}
			return 0, nil, context.DeadlineExceeded
		}
		return 0, nil, err
	}
	return code, data, nil
}

func encodeRLP(msg any) ([]byte, error) {
	return rlp.EncodeToBytes(msg)
}

func writePayload(ctx context.Context, conn *rlpx.Conn, code uint64, payload []byte) error {
	conn.SetWriteDeadline(deadlineFrom(ctx))
	_, err := conn.Write(code, payload)
	return err
}

func writeRLP(ctx context.Context, conn *rlpx.Conn, code uint64, msg any) error {
	payload, err := encodeRLP(msg)
	if err != nil {
		return err
	}
	return writePayload(ctx, conn, code, payload)
}

func writePong(ctx context.Context, conn *rlpx.Conn) error {
	return writeRLP(ctx, conn, pongMsg, []any{})
}

func capsToStrings(caps []p2p.Cap) []string {
	out := make([]string, len(caps))
	for i, cap := range caps {
		out[i] = cap.String()
	}
	return out
}

func helloCaps(ethVersion uint) []p2p.Cap {
	caps := []p2p.Cap{
		{Name: "wit", Version: witVersion2},
		{Name: "wit", Version: witVersion1},
	}
	switch ethVersion {
	case ethVersion69:
		return append([]p2p.Cap{{Name: "eth", Version: ethVersion69}}, caps...)
	default:
		return append([]p2p.Cap{{Name: "eth", Version: ethVersion68}}, caps...)
	}
}

func negotiateVersion(remote []p2p.Cap, name string, local []uint) uint {
	var best uint
	for _, want := range local {
		for _, cap := range remote {
			if cap.Name == name && cap.Version == want && cap.Version > best {
				best = cap.Version
			}
		}
	}
	return best
}

func ethOffset() uint64 {
	return baseProtocolLength
}

func witOffset() uint64 {
	return baseProtocolLength + ethProtocolLength
}

func deadlineFrom(ctx context.Context) time.Time {
	if dl, ok := ctx.Deadline(); ok {
		return dl
	}
	return time.Now().Add(defaultTimeout)
}

func remainingOr(ctx context.Context, fallback time.Duration) time.Duration {
	if dl, ok := ctx.Deadline(); ok {
		if remaining := time.Until(dl); remaining > 0 {
			return remaining
		}
	}
	return fallback
}

func classifyPeerError(err error) string {
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	default:
		return "disconnect"
	}
}

func decodeDisconnect(data []byte, context string) error {
	var (
		sliceReason  []uint64
		singleReason uint64
	)
	if err := rlp.DecodeBytes(data, &sliceReason); err == nil && len(sliceReason) > 0 {
		reason := p2p.DiscReason(sliceReason[0])
		if context == "" {
			return reason
		}
		return fmt.Errorf("%s %s", reason, context)
	}
	if err := rlp.DecodeBytes(data, &singleReason); err == nil {
		reason := p2p.DiscReason(singleReason)
		if context == "" {
			return reason
		}
		return fmt.Errorf("%s %s", reason, context)
	}
	if context == "" {
		return fmt.Errorf("disconnect received (raw=%#x)", data)
	}
	return fmt.Errorf("disconnect received %s (raw=%#x)", context, data)
}

func disconnectReason(err error) string {
	var reason p2p.DiscReason
	if errors.As(err, &reason) {
		return reason.String()
	}
	return ""
}

func newForkID(genesisHash common.Hash, genesisTime uint64, cfg *chainConfig, head, now uint64) forkid.ID {
	hash := crc32.ChecksumIEEE(genesisHash.Bytes())
	blockForks, timeForks := gatherForks(cfg, genesisTime)

	for _, fork := range blockForks {
		if fork <= head {
			hash = checksumUpdate(hash, fork)
			continue
		}
		return forkid.ID{Hash: checksumToBytes(hash), Next: fork}
	}
	for _, fork := range timeForks {
		if fork <= now {
			hash = checksumUpdate(hash, fork)
			continue
		}
		return forkid.ID{Hash: checksumToBytes(hash), Next: fork}
	}
	return forkid.ID{Hash: checksumToBytes(hash), Next: 0}
}

func gatherForks(cfg *chainConfig, genesisTime uint64) ([]uint64, []uint64) {
	blockForks := compactSortedForks([]uint64{
		bigIntToUint64(cfg.HomesteadBlock),
		bigIntToUint64(cfg.DAOForkBlock),
		bigIntToUint64(cfg.EIP150Block),
		bigIntToUint64(cfg.EIP155Block),
		bigIntToUint64(cfg.EIP158Block),
		bigIntToUint64(cfg.ByzantiumBlock),
		bigIntToUint64(cfg.ConstantinopleBlock),
		bigIntToUint64(cfg.PetersburgBlock),
		bigIntToUint64(cfg.IstanbulBlock),
		bigIntToUint64(cfg.MuirGlacierBlock),
		bigIntToUint64(cfg.BerlinBlock),
		bigIntToUint64(cfg.LondonBlock),
		bigIntToUint64(cfg.ArrowGlacierBlock),
		bigIntToUint64(cfg.GrayGlacierBlock),
		bigIntToUint64(cfg.MergeNetsplitBlock),
		bigIntToUint64(cfg.ShanghaiBlock),
		bigIntToUint64(cfg.CancunBlock),
		bigIntToUint64(cfg.PragueBlock),
		bigIntToUint64(cfg.VerkleBlock),
	})
	timeForks := compactSortedForks([]uint64{
		uint64PtrValue(cfg.ShanghaiTime),
		uint64PtrValue(cfg.CancunTime),
		uint64PtrValue(cfg.PragueTime),
		uint64PtrValue(cfg.VerkleTime),
	})
	for len(timeForks) > 0 && timeForks[0] <= genesisTime {
		timeForks = timeForks[1:]
	}
	return blockForks, timeForks
}

func compactSortedForks(forks []uint64) []uint64 {
	out := forks[:0]
	for _, fork := range forks {
		if fork > 0 {
			out = append(out, fork)
		}
	}
	slices.Sort(out)
	return slices.Compact(out)
}

func bigIntToUint64(v *big.Int) uint64 {
	if v == nil {
		return 0
	}
	return v.Uint64()
}

func uint64PtrValue(v *uint64) uint64 {
	if v == nil {
		return 0
	}
	return *v
}

func checksumUpdate(hash uint32, fork uint64) uint32 {
	var blob [8]byte
	binary.BigEndian.PutUint64(blob[:], fork)
	return crc32.Update(hash, crc32.IEEETable, blob[:])
}

func checksumToBytes(hash uint32) [4]byte {
	var blob [4]byte
	binary.BigEndian.PutUint32(blob[:], hash)
	return blob
}

func negotiatedWitOffset(cfg *flags, negEth uint) uint64 {
	if cfg.witOffset != 0 {
		return cfg.witOffset
	}
	return baseProtocolLength + negotiatedEthLength(negEth)
}

func negotiatedEthLength(version uint) uint64 {
	switch version {
	case ethVersion69:
		return ethProtocolLength
	case ethVersion68:
		return 17
	default:
		return ethProtocolLength
	}
}

func writeAndExit(res result, code int) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(res); err != nil {
		fmt.Fprintf(os.Stderr, "{\"outcome\":\"encode_error\",\"error\":%q}\n", err.Error())
		os.Exit(1)
	}
	os.Exit(code)
}
