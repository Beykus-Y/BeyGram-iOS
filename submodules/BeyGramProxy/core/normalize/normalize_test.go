// This file is part of BeyGram and is distributed under the GNU General Public License v3.0.
// See submodules/BeyGramProxy/LICENSE and the NOTICE file at the repository root.

package normalize

import (
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

var testCreds = Credentials{Username: "user-test", Password: "pass-test"}

const sampleURIList = `# subscription comment
vless://11111111-2222-3333-4444-555555555555@example.com:443?type=tcp&security=reality&pbk=PUBKEY&sid=ab&sni=www.example.com&fp=chrome&flow=xtls-rprx-vision#Node%20One
ss://YWVzLTI1Ni1nY206c2VjcmV0@198.51.100.7:8388#SS
trojan://pass%40word@trojan.example.net:443?sni=trojan.example.net#Trojan
hysteria2://hy-pass@hy.example.org:8443/?sni=hy.example.org&obfs=salamander&obfs-password=obf#Hy
tuic://uuid-1:tuic-pass@tuic.example.io:443?alpn=h3&congestion_control=bbr#Tuic
this is not a link
`

const clashYAML = `mixed-port: 7890
port: 7891
external-controller: 127.0.0.1:9090
secret: abc
allow-lan: true
tun:
  enable: true
  stack: system
dns:
  enable: true
  nameserver:
    - 1.1.1.1
proxies:
  - name: "Frankfurt"
    type: ss
    server: fra.example.com
    port: 443
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: Auto
    type: select
    proxies: [Frankfurt]
rules:
  - MATCH,Auto
`

func parseOutput(t *testing.T, out string) map[string]any {
	t.Helper()
	var doc map[string]any
	if err := yaml.Unmarshal([]byte(out), &doc); err != nil {
		t.Fatalf("output is not YAML: %v\n%s", err, out)
	}
	return doc
}

func findGroup(t *testing.T, doc map[string]any, name string) map[string]any {
	t.Helper()
	groups, _ := doc["proxy-groups"].([]any)
	for _, item := range groups {
		if group, ok := item.(map[string]any); ok && group["name"] == name {
			return group
		}
	}
	t.Fatalf("group %q not found", name)
	return nil
}

func findProxy(t *testing.T, doc map[string]any, name string) map[string]any {
	t.Helper()
	proxies, _ := doc["proxies"].([]any)
	for _, item := range proxies {
		if proxy, ok := item.(map[string]any); ok && proxy["name"] == name {
			return proxy
		}
	}
	t.Fatalf("proxy %q not found", name)
	return nil
}

func assertForcedSettings(t *testing.T, doc map[string]any) {
	t.Helper()
	if doc["allow-lan"] != false {
		t.Errorf("allow-lan = %v, want false", doc["allow-lan"])
	}
	if doc["bind-address"] != Host {
		t.Errorf("bind-address = %v, want %s", doc["bind-address"], Host)
	}
	if doc["socks-port"] != Port {
		t.Errorf("socks-port = %v, want %d", doc["socks-port"], Port)
	}
	auth, _ := doc["authentication"].([]any)
	if len(auth) != 1 || auth[0] != "user-test:pass-test" {
		t.Errorf("authentication = %v", auth)
	}
	if _, present := doc["external-controller"]; present {
		t.Error("external-controller must be removed")
	}
	if _, present := doc["secret"]; present {
		t.Error("secret must be removed")
	}
	tun, _ := doc["tun"].(map[string]any)
	if tun["enable"] != false {
		t.Errorf("tun.enable = %v, want false", tun["enable"])
	}
	dns, _ := doc["dns"].(map[string]any)
	if ns, _ := dns["proxy-server-nameserver"].([]any); len(ns) != 1 || ns[0] != "system" {
		t.Errorf("dns.proxy-server-nameserver = %v", dns["proxy-server-nameserver"])
	}
	if doc["mode"] != "rule" {
		t.Errorf("mode = %v", doc["mode"])
	}
	rules, _ := doc["rules"].([]any)
	if len(rules) != 1 || rules[0] != "MATCH,"+ConnectionGroup {
		t.Errorf("rules = %v", rules)
	}
}

func TestPlainURIListIsConverted(t *testing.T) {
	result, err := Normalize(sampleURIList, testCreds)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if len(result.Servers) != 5 {
		t.Fatalf("servers = %d, want 5", len(result.Servers))
	}
	if result.Skipped != 1 {
		t.Fatalf("skipped = %d, want 1", result.Skipped)
	}
	doc := parseOutput(t, result.YAML)
	assertForcedSettings(t, doc)

	vless := findProxy(t, doc, "Node One")
	if vless["type"] != "vless" || vless["server"] != "example.com" || vless["port"] != 443 {
		t.Errorf("vless = %v", vless)
	}
	if vless["uuid"] != "11111111-2222-3333-4444-555555555555" || vless["flow"] != "xtls-rprx-vision" {
		t.Errorf("vless identity = %v", vless)
	}
	if vless["tls"] != true || vless["servername"] != "www.example.com" || vless["client-fingerprint"] != "chrome" {
		t.Errorf("vless tls = %v", vless)
	}
	reality, _ := vless["reality-opts"].(map[string]any)
	if reality["public-key"] != "PUBKEY" || reality["short-id"] != "ab" {
		t.Errorf("reality-opts = %v", reality)
	}

	ss := findProxy(t, doc, "SS")
	if ss["cipher"] != "aes-256-gcm" || ss["password"] != "secret" || ss["server"] != "198.51.100.7" {
		t.Errorf("ss = %v", ss)
	}

	trojan := findProxy(t, doc, "Trojan")
	if trojan["password"] != "pass@word" || trojan["servername"] != "trojan.example.net" {
		t.Errorf("trojan = %v", trojan)
	}

	hy := findProxy(t, doc, "Hy")
	if hy["type"] != "hysteria2" || hy["password"] != "hy-pass" || hy["obfs"] != "salamander" {
		t.Errorf("hysteria2 = %v", hy)
	}

	tuic := findProxy(t, doc, "Tuic")
	if tuic["uuid"] != "uuid-1" || tuic["password"] != "tuic-pass" || tuic["congestion-controller"] != "bbr" {
		t.Errorf("tuic = %v", tuic)
	}

	group := findGroup(t, doc, ConnectionGroup)
	if group["type"] != "select" || group["include-all"] != true {
		t.Errorf("group = %v", group)
	}
}

func TestBase64OfURIListIsConverted(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString([]byte(sampleURIList))
	result, err := Normalize(encoded, testCreds)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if len(result.Servers) != 5 {
		t.Fatalf("servers = %d, want 5", len(result.Servers))
	}
}

func TestClashYAMLIsNormalized(t *testing.T) {
	result, err := Normalize(clashYAML, testCreds)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	if len(result.Servers) != 1 || result.Servers[0].Name != "Frankfurt" || result.Servers[0].Port != 443 {
		t.Fatalf("servers = %+v", result.Servers)
	}
	doc := parseOutput(t, result.YAML)
	assertForcedSettings(t, doc)
	if doc["mixed-port"] != 0 || doc["port"] != 0 {
		t.Errorf("mixed-port/port = %v/%v, want 0", doc["mixed-port"], doc["port"])
	}
	tun, _ := doc["tun"].(map[string]any)
	if tun["stack"] != "system" {
		t.Errorf("tun.stack lost: %v", tun)
	}
	dns, _ := doc["dns"].(map[string]any)
	if ns, _ := dns["nameserver"].([]any); len(ns) != 1 || ns[0] != "1.1.1.1" {
		t.Errorf("dns.nameserver lost: %v", dns)
	}
	auto := findGroup(t, doc, "Auto")
	if auto["type"] != "select" {
		t.Errorf("existing group changed: %v", auto)
	}
	findGroup(t, doc, ConnectionGroup)
}

func TestExistingGroupNameMustBeSelect(t *testing.T) {
	source := `proxies:
  - name: A
    type: ss
    server: a.example.com
    port: 1
    cipher: aes-128-gcm
    password: p
proxy-groups:
  - name: BeyGram Telegram
    type: url-test
    proxies: [A]
`
	if _, err := Normalize(source, testCreds); err == nil || !strings.Contains(err.Error(), "уже есть группа") {
		t.Fatalf("err = %v, want group conflict", err)
	}
}

func TestVMessLinkIsConverted(t *testing.T) {
	fields := map[string]any{
		"v": "2", "ps": "VM", "add": "vm.example.com", "port": "443", "id": "uuid-vm",
		"aid": "0", "net": "ws", "tls": "tls", "sni": "vm.example.com", "path": "/ws", "host": "vm.example.com",
	}
	raw, err := json.Marshal(fields)
	if err != nil {
		t.Fatal(err)
	}
	link := "vmess://" + base64.StdEncoding.EncodeToString(raw)
	result, err := Normalize(link, testCreds)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	doc := parseOutput(t, result.YAML)
	vm := findProxy(t, doc, "VM")
	if vm["type"] != "vmess" || vm["uuid"] != "uuid-vm" || vm["tls"] != true {
		t.Errorf("vmess = %v", vm)
	}
	wsOpts, _ := vm["ws-opts"].(map[string]any)
	if wsOpts["path"] != "/ws" {
		t.Errorf("ws-opts = %v", wsOpts)
	}
}

func TestXHTTPOptionsAreMapped(t *testing.T) {
	source := "vless://id@x.example.com:443?type=xhttp&path=%2Fx&mode=packet-up&xPaddingBytes=100-1000&sessionLength=30&headers=X-A:1,X-B:2#X"
	result, err := Normalize(source, testCreds)
	if err != nil {
		t.Fatalf("Normalize: %v", err)
	}
	doc := parseOutput(t, result.YAML)
	node := findProxy(t, doc, "X")
	if node["network"] != "xhttp" {
		t.Fatalf("network = %v", node["network"])
	}
	opts, _ := node["xhttp-opts"].(map[string]any)
	if opts["path"] != "/x" || opts["mode"] != "packet-up" || opts["x-padding-bytes"] != "100-1000" {
		t.Errorf("xhttp-opts = %v", opts)
	}
	if opts["session-length"] != 30 {
		t.Errorf("session-length = %v (%T), want int 30", opts["session-length"], opts["session-length"])
	}
	headers, _ := opts["headers"].(map[string]any)
	if headers["X-A"] != "1" || headers["X-B"] != "2" {
		t.Errorf("headers = %v", headers)
	}
}

func TestRefusals(t *testing.T) {
	cases := map[string]string{
		"empty":         "   \n",
		"garbage":       "hello world",
		"duplicate key": "a: 1\na: 2\n",
		"no servers":    "# only a comment\n",
	}
	for name, source := range cases {
		if _, err := Normalize(source, testCreds); err == nil {
			t.Errorf("%s: expected a refusal", name)
		}
	}
	if _, err := Normalize(sampleURIList, Credentials{}); err == nil {
		t.Error("missing credentials must be refused")
	}
	long := strings.Repeat("a", MaxProfileBytes+1)
	if _, err := Normalize(long, testCreds); err == nil {
		t.Error("oversized source must be refused")
	}
}
