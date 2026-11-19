package bridge

import (
	"encoding/base64"
	"encoding/json"
	"net"
	"strconv"
	"strings"
	"testing"

	"beygram/mihomoproxy/normalize"
)

// testRealityKey is a well-formed X25519 public key (32 bytes, unpadded base64url).
// Mihomo rejects malformed REALITY keys while parsing, so the fixture must use one.
var testRealityKey = base64.RawURLEncoding.EncodeToString(append([]byte{9}, make([]byte, 31)...))

var sampleSubscription = "vless://11111111-2222-3333-4444-555555555555@example.com:443?type=tcp&security=reality&pbk=" +
	testRealityKey + "&sid=ab&sni=www.example.com&fp=chrome&flow=xtls-rprx-vision#Node%20One\n" +
	"ss://YWVzLTI1Ni1nY206c2VjcmV0@198.51.100.7:8388#SS\n" +
	"trojan://pass%40word@trojan.example.net:443?sni=trojan.example.net#Trojan\n"

type testReply struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
}

func call(t *testing.T, core *Core, method string, data map[string]any) testReply {
	t.Helper()
	raw, err := json.Marshal(map[string]any{"id": "1", "method": method, "data": data})
	if err != nil {
		t.Fatal(err)
	}
	var reply testReply
	if err := json.Unmarshal(core.Invoke(raw), &reply); err != nil {
		t.Fatalf("%s: reply is not JSON: %v", method, err)
	}
	return reply
}

func mustOK(t *testing.T, core *Core, method string, data map[string]any) json.RawMessage {
	t.Helper()
	reply := call(t, core, method, data)
	if reply.Code != 0 {
		t.Fatalf("%s: code %d: %s", method, reply.Code, reply.Message)
	}
	return reply.Data
}

func normalizedProfile(t *testing.T) string {
	t.Helper()
	result, err := normalize.Normalize(sampleSubscription, normalize.Credentials{Username: "user-test", Password: "pass-test"})
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	return result.YAML
}

func TestActionsNeedInit(t *testing.T) {
	core := New()
	reply := call(t, core, "validate", map[string]any{"config": "mode: rule\n"})
	if reply.Code == 0 || !strings.Contains(reply.Message, "не инициализировано") {
		t.Fatalf("validate before init: code %d, message %q", reply.Code, reply.Message)
	}
}

func TestUnknownMethodIsRefused(t *testing.T) {
	core := New()
	if reply := call(t, core, "nope", nil); reply.Code == 0 {
		t.Fatal("unknown method must be refused")
	}
}

func TestNormalizedProfileValidates(t *testing.T) {
	core := New()
	mustOK(t, core, "init", map[string]any{"home-dir": t.TempDir()})
	out := mustOK(t, core, "normalize", map[string]any{
		"source": sampleSubscription, "username": "user-test", "password": "pass-test",
	})
	var normalized struct {
		YAML    string `json:"yaml"`
		Servers []any  `json:"servers"`
	}
	if err := json.Unmarshal(out, &normalized); err != nil {
		t.Fatal(err)
	}
	if len(normalized.Servers) != 3 || !strings.Contains(normalized.YAML, "BeyGram Telegram") {
		t.Fatalf("normalize output: %d servers, yaml %q", len(normalized.Servers), normalized.YAML)
	}
	mustOK(t, core, "validate", map[string]any{"config": normalized.YAML})
	if reply := call(t, core, "validate", map[string]any{"config": "proxies: [\n"}); reply.Code == 0 {
		t.Fatal("broken YAML must be refused")
	}
}

func TestInletLifecycle(t *testing.T) {
	core := New()
	mustOK(t, core, "init", map[string]any{"home-dir": t.TempDir()})
	t.Cleanup(func() { call(t, core, "stop", nil) })

	mustOK(t, core, "setup", map[string]any{
		"config":   normalizedProfile(t),
		"selected": map[string]string{"BeyGram Telegram": "SS"},
	})
	if status := mustOK(t, core, "status", nil); !strings.Contains(string(status), `"running":true`) {
		t.Fatalf("status after setup = %s", status)
	}

	var list struct {
		Now   string `json:"now"`
		Nodes []struct {
			Name string `json:"name"`
		} `json:"nodes"`
	}
	if err := json.Unmarshal(mustOK(t, core, "proxies", map[string]any{"group": "BeyGram Telegram"}), &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Nodes) != 3 || list.Now != "SS" {
		t.Fatalf("proxies: now %q, %d nodes", list.Now, len(list.Nodes))
	}

	mustOK(t, core, "select", map[string]any{"group": "BeyGram Telegram", "proxy": "Trojan"})
	if reply := call(t, core, "select", map[string]any{"group": "BeyGram Telegram", "proxy": "missing"}); reply.Code == 0 {
		t.Fatal("selecting an unknown node must fail")
	}

	delay := mustOK(t, core, "testDelay", map[string]any{"proxy-name": "SS", "timeout": 1000})
	if !strings.Contains(string(delay), `"delay"`) {
		t.Fatalf("testDelay = %s", delay)
	}

	mustOK(t, core, "stop", nil)
	if status := mustOK(t, core, "status", nil); !strings.Contains(string(status), `"running":false`) {
		t.Fatalf("status after stop = %s", status)
	}
	address := net.JoinHostPort(normalize.Host, strconv.Itoa(normalize.Port))
	if conn, err := net.Dial("tcp", address); err == nil {
		_ = conn.Close()
		t.Fatalf("the inlet on %s still accepts connections after stop", address)
	}
}
