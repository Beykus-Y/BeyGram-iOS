// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

// Package bridge runs Mihomo in-process behind one JSON request and one JSON reply.
//
// The action names and the reply envelope follow the libmihomo-android bridge
// that BeyGram uses on Android, so both platforms speak the same protocol.
// Mihomo has no external controller here: the profile from package normalize
// drops external-controller and secret, and the only listener is the SOCKS5
// inlet on 127.0.0.1, which requires the credentials written into the profile.
//
// Actions (data in, result out):
//
//	init              {"home-dir"}                           set the core's home directory
//	normalize         {"source", "username", "password"}     subscription to profile YAML; keeps no core state
//	validate          {"config"}                             parse a profile without starting it
//	setup             {"config", "selected"}                 apply a profile and start the inlet
//	stop              {}                                     close the inlet and its connections
//	status            {}                                     {"running"}
//	proxies           {"group"}                              {"now", "nodes": [{"name", "type", "delay"}]}
//	select            {"group", "proxy"}                     choose a node of a select group
//	testDelay         {"proxy-name", "test-url", "timeout"}  {"delay"} in ms, -1 on failure
//	resetConnections  {}                                     close tracked connections
//
// A reply is {"id", "code", "data"} with code 0, or {"id", "code": 1, "message"}.
package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strconv"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/utils"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"

	"beygram/mihomoproxy/normalize"
)

const (
	defaultTestURL   = "https://web.telegram.org/"
	defaultTimeoutMS = 5000
	minProbeTimeout  = time.Second
	maxProbeTimeout  = 15 * time.Second
	inletDialTimeout = 500 * time.Millisecond
)

// Core owns the in-process Mihomo instance. Every call takes the mutex, so
// Mihomo never runs two actions at once.
type Core struct {
	mu        sync.Mutex
	homeReady bool
	running   bool
}

// New returns a core that still needs the init action.
func New() *Core {
	return &Core{}
}

type request struct {
	ID     string          `json:"id"`
	Method string          `json:"method"`
	Data   json.RawMessage `json:"data"`
}

type reply struct {
	ID      string `json:"id"`
	Code    int    `json:"code"`
	Message string `json:"message,omitempty"`
	Data    any    `json:"data"`
}

// Invoke handles one request and returns one reply, both as JSON.
func (c *Core) Invoke(raw []byte) []byte {
	var req request
	if err := json.Unmarshal(raw, &req); err != nil {
		return encode(reply{Code: 1, Message: "некорректный запрос"})
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	data, err := c.safeDispatch(req.Method, req.Data)
	if err != nil {
		return encode(reply{ID: req.ID, Code: 1, Message: err.Error()})
	}
	return encode(reply{ID: req.ID, Code: 0, Data: data})
}

func encode(r reply) []byte {
	out, err := json.Marshal(r)
	if err != nil {
		return []byte(`{"code":1,"message":"не удалось закодировать ответ"}`)
	}
	return out
}

// safeDispatch turns a panic inside Mihomo into an error reply. A panic must
// not cross the cgo boundary, because it would end the whole app.
func (c *Core) safeDispatch(method string, data json.RawMessage) (result any, err error) {
	defer func() {
		if r := recover(); r != nil {
			result, err = nil, fmt.Errorf("внутренняя ошибка ядра: %v", r)
		}
	}()
	return c.dispatch(method, data)
}

func (c *Core) dispatch(method string, data json.RawMessage) (any, error) {
	switch method {
	case "init":
		return nil, c.initialize(data)
	case "normalize":
		return normalizeProfile(data)
	case "validate":
		return nil, c.validate(data)
	case "setup":
		return nil, c.setup(data)
	case "stop":
		return nil, c.stop()
	case "status":
		return map[string]any{"running": c.running}, nil
	case "proxies":
		return proxies(data)
	case "select":
		return nil, selectNode(data)
	case "testDelay":
		return testDelay(data)
	case "resetConnections":
		resetConnections()
		return nil, nil
	default:
		return nil, fmt.Errorf("неизвестный метод %q", method)
	}
}

func (c *Core) initialize(data json.RawMessage) error {
	var args struct {
		HomeDir string `json:"home-dir"`
	}
	if err := json.Unmarshal(data, &args); err != nil || args.HomeDir == "" {
		return errors.New("не задана папка ядра")
	}
	C.SetHomeDir(args.HomeDir)
	c.homeReady = true
	return nil
}

func normalizeProfile(data json.RawMessage) (any, error) {
	var args struct {
		Source   string `json:"source"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.Unmarshal(data, &args); err != nil {
		return nil, errors.New("некорректные данные подписки")
	}
	result, err := normalize.Normalize(args.Source, normalize.Credentials{Username: args.Username, Password: args.Password})
	if err != nil {
		return nil, err
	}
	servers := make([]map[string]any, 0, len(result.Servers))
	for _, server := range result.Servers {
		servers = append(servers, map[string]any{
			"name": server.Name, "type": server.Type, "server": server.Server, "port": server.Port,
		})
	}
	return map[string]any{"yaml": result.YAML, "servers": servers, "skipped": result.Skipped}, nil
}

// profileText reads the "config" field of a request.
func profileText(data json.RawMessage) (string, error) {
	var args struct {
		Config string `json:"config"`
	}
	if err := json.Unmarshal(data, &args); err != nil || args.Config == "" {
		return "", errors.New("пустой профиль")
	}
	return args.Config, nil
}

func (c *Core) validate(data json.RawMessage) error {
	if !c.homeReady {
		return errors.New("ядро не инициализировано")
	}
	text, err := profileText(data)
	if err != nil {
		return err
	}
	_, err = executor.ParseWithBytes([]byte(text))
	return err
}

func (c *Core) setup(data json.RawMessage) error {
	if !c.homeReady {
		return errors.New("ядро не инициализировано")
	}
	text, err := profileText(data)
	if err != nil {
		return err
	}
	var args struct {
		Selected map[string]string `json:"selected"`
	}
	_ = json.Unmarshal(data, &args) // the selection is optional
	parsed, err := executor.ParseWithBytes([]byte(text))
	if err != nil {
		return err
	}
	// ApplyConfig recreates the listeners that the profile describes. It reports
	// nothing, so the inlet is probed below.
	executor.ApplyConfig(parsed, true)
	c.running = true
	restoreSelection(args.Selected)
	if err := probeInlet(); err != nil {
		_ = c.stop()
		return err
	}
	return nil
}

func (c *Core) stop() error {
	// Mihomo's Shutdown does not close the SOCKS listeners. Re-creating them with
	// port 0 does.
	listener.ReCreateHTTP(0, tunnel.Tunnel)
	listener.ReCreateSocks(0, tunnel.Tunnel)
	listener.ReCreateMixed(0, tunnel.Tunnel)
	resetConnections()
	c.running = false
	return nil
}

// restoreSelection re-applies the node the user chose in each select group.
// A node that the new profile no longer has leaves its group on the default.
func restoreSelection(selected map[string]string) {
	for group, name := range selected {
		if selector, err := findSelector(group); err == nil {
			_ = selector.Set(name)
		}
	}
}

// probeInlet checks that the loopback inlet accepts connections.
func probeInlet() error {
	address := net.JoinHostPort(normalize.Host, strconv.Itoa(normalize.Port))
	conn, err := net.DialTimeout("tcp", address, inletDialTimeout)
	if err != nil {
		return fmt.Errorf("локальный вход ядра не открылся: %w", err)
	}
	return conn.Close()
}

func proxies(data json.RawMessage) (any, error) {
	var args struct {
		Group string `json:"group"`
	}
	if err := json.Unmarshal(data, &args); err != nil {
		return nil, errors.New("некорректный запрос")
	}
	group, err := findGroup(args.Group)
	if err != nil {
		return nil, err
	}
	nodes := make([]map[string]any, 0)
	for _, node := range group.Proxies() {
		if !isServer(node) {
			continue
		}
		nodes = append(nodes, map[string]any{
			"name":  node.Name(),
			"type":  node.Type().String(),
			"delay": lastDelay(node),
		})
	}
	return map[string]any{"now": group.Now(), "nodes": nodes}, nil
}

func selectNode(data json.RawMessage) error {
	var args struct {
		Group string `json:"group"`
		Proxy string `json:"proxy"`
	}
	if err := json.Unmarshal(data, &args); err != nil {
		return errors.New("некорректный запрос")
	}
	selector, err := findSelector(args.Group)
	if err != nil {
		return err
	}
	if err := selector.Set(args.Proxy); err != nil {
		return err
	}
	resetConnections()
	return nil
}

func testDelay(data json.RawMessage) (any, error) {
	var args struct {
		ProxyName string `json:"proxy-name"`
		TestURL   string `json:"test-url"`
		Timeout   int    `json:"timeout"`
	}
	if err := json.Unmarshal(data, &args); err != nil || args.ProxyName == "" {
		return nil, errors.New("не задан сервер")
	}
	node, ok := tunnel.Proxies()[args.ProxyName]
	if !ok {
		return nil, errors.New("сервер не найден")
	}
	testURL := args.TestURL
	if testURL == "" {
		testURL = defaultTestURL
	}
	timeout := defaultTimeoutMS * time.Millisecond
	if args.Timeout > 0 {
		timeout = time.Duration(args.Timeout) * time.Millisecond
	}
	timeout = min(max(timeout, minProbeTimeout), maxProbeTimeout)
	expected, err := utils.NewUnsignedRanges[uint16]("200-399")
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	delay, err := node.URLTest(ctx, testURL, expected)
	if err != nil {
		return map[string]any{"delay": -1, "error": err.Error()}, nil
	}
	return map[string]any{"delay": int(delay)}, nil
}

// findGroup returns the proxy group with the given name.
func findGroup(name string) (outboundgroup.ProxyGroup, error) {
	node, ok := tunnel.Proxies()[name]
	if !ok {
		return nil, errors.New("группа серверов не найдена")
	}
	group, ok := node.Adapter().(outboundgroup.ProxyGroup)
	if !ok {
		return nil, errors.New("это не группа серверов")
	}
	return group, nil
}

// findSelector returns a select group, the only kind the user chooses from.
// Url-test and fallback groups pick their node themselves.
func findSelector(name string) (outboundgroup.SelectAble, error) {
	node, ok := tunnel.Proxies()[name]
	if !ok {
		return nil, errors.New("группа серверов не найдена")
	}
	selector, ok := node.Adapter().(outboundgroup.SelectAble)
	if !ok || node.Type() != C.Selector {
		return nil, errors.New("группа серверов не поддерживает выбор")
	}
	return selector, nil
}

// isServer reports whether a node is a real server rather than a group or a built-in outlet.
func isServer(node C.Proxy) bool {
	if _, nested := node.Adapter().(outboundgroup.ProxyGroup); nested {
		return false
	}
	switch node.Type() {
	case C.Direct, C.Reject, C.RejectDrop, C.Compatible, C.Pass:
		return false
	}
	return true
}

// lastDelay returns the newest measured delay in ms, or -1 when none is known.
func lastDelay(node C.Proxy) int {
	history := node.DelayHistory()
	if len(history) == 0 || history[len(history)-1].Delay == 0 {
		return -1
	}
	return int(history[len(history)-1].Delay)
}

// resetConnections closes every tracked connection. Trackers are collected first,
// so that Close does not run while the manager is being iterated.
func resetConnections() {
	var trackers []statistic.Tracker
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		trackers = append(trackers, tracker)
		return true
	})
	for _, tracker := range trackers {
		_ = tracker.Close()
	}
}
