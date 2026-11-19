// Package normalize turns a provider subscription into the Mihomo profile that
// BeyGram runs as an app-local SOCKS5 listener.
//
// It is a port of the Android MihomoProfileNormalizer. Both platforms must keep
// the same forced settings: no remote listeners, no external controller, no TUN,
// a loopback listener that requires per-installation credentials, and a single
// selectable group that routes everything entering the listener.
package normalize

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"gopkg.in/yaml.v3"
)

const (
	// Host and Port are the loopback address and port of the app-local SOCKS5 listener.
	Host = "127.0.0.1"
	Port = 17891

	// ConnectionGroup is the selectable group that every connection uses.
	ConnectionGroup = "BeyGram Telegram"

	// MaxProfileBytes bounds both the downloaded subscription and the decoded text.
	MaxProfileBytes = 5 * 1024 * 1024

	logLevel        = "warning"
	minBase64Length = 16
	maxNameRunes    = 96
)

// removedKeys are dropped: they open remote listeners, the external controller,
// or server ports that the subscription must not control. Shortcut inbounds
// (ss-config, vmess-config, tuic-server) open server ports through their values.
var removedKeys = []string{
	"external-controller", "external-controller-tls", "external-controller-unix",
	"external-controller-pipe", "secret", "authentication", "skip-auth-prefixes",
	"listeners", "ss-config", "vmess-config", "tuic-server",
}

// zeroedPortKeys are set to 0 when present, so that only the app-local listener is open.
var zeroedPortKeys = []string{"port", "mixed-port", "redir-port", "tproxy-port", "tun-port"}

var base64Document = regexp.MustCompile(`^[A-Za-z0-9_+/=-]+$`)

// Credentials protect the loopback listener: every app on the device can reach 127.0.0.1.
type Credentials struct {
	Username string
	Password string
}

// Server describes one outbound node of the profile.
type Server struct {
	Name   string
	Type   string
	Server string
	Port   int
}

// Result is a normalized profile. YAML is the text the core runs.
type Result struct {
	YAML    string
	Servers []Server
	// Skipped counts lines of a plain URI list that could not be converted.
	Skipped int
}

// Error is a refusal. Message is safe to show to the user; Detail is for diagnostics.
type Error struct {
	Message string
	Detail  string
}

func (e *Error) Error() string { return e.Message }

func refuse(message, detail string) error { return &Error{Message: message, Detail: detail} }

// Normalize validates a provider document and returns the profile BeyGram runs.
// The input may be a Clash/Mihomo YAML object, a plain list of proxy URIs, or
// Base64 of either.
func Normalize(source string, creds Credentials) (Result, error) {
	if strings.TrimSpace(source) == "" {
		return Result{}, refuse("Подписка пустая", "empty source")
	}
	if len(source) > MaxProfileBytes {
		return Result{}, refuse("Подписка слишком большая (больше 5 МБ)", "source too large")
	}
	if creds.Username == "" || creds.Password == "" {
		return Result{}, refuse("Нет данных для входа в локальный прокси", "missing credentials")
	}

	skipped := 0
	root, isObject := parseObject(source)
	if !isObject {
		// A plain list of proxy URIs is not a YAML object, so it is read before the text is treated as Base64.
		if list := parseURIList(source); len(list.proxies) > 0 {
			root, skipped = map[string]any{"proxies": list.proxies}, list.skipped
		}
	}
	if root == nil {
		decoded, ok := decodeBase64Document(source)
		if !ok {
			return Result{}, refuse("Ссылка не похожа на подписку с серверами", "not a subscription")
		}
		var decodedIsObject bool
		root, decodedIsObject = parseObject(decoded)
		if !decodedIsObject {
			list := parseURIList(decoded)
			if len(list.proxies) == 0 {
				return Result{}, refuse("В подписке нет серверов, которые можно использовать", "no usable servers")
			}
			root, skipped = map[string]any{"proxies": list.proxies}, list.skipped
		}
	}

	config := make(map[string]any, len(root)+8)
	for key, value := range root {
		config[key] = value
	}

	// Keep the app-facing proxy private to this process: the core uses an explicit
	// loopback SOCKS inlet, and no transparent TUN is created.
	config["allow-lan"] = false
	config["bind-address"] = Host
	for _, key := range removedKeys {
		delete(config, key)
	}
	for _, key := range zeroedPortKeys {
		if _, present := config[key]; present {
			config[key] = 0
		}
	}
	config["socks-port"] = Port
	// Every app on the device can reach the loopback port, so the listener requires per-installation credentials.
	config["authentication"] = []string{creds.Username + ":" + creds.Password}
	// Set explicitly: when the key is absent, the core default may exempt loopback clients from the credentials.
	config["skip-auth-prefixes"] = []string{}
	// Keep the core's warnings and errors, such as a failed listener bind.
	config["log-level"] = logLevel
	// Node hostnames must use the device's active resolver. Provider DNS endpoints may be
	// blocked on mobile networks and would otherwise prevent every proxy from dialing.
	config["dns"] = withEntry(config["dns"], "proxy-server-nameserver", []string{"system"})
	config["tun"] = withEntry(config["tun"], "enable", false)

	groups, _ := config["proxy-groups"].([]any)
	groupIndex := -1
	for index, group := range groups {
		if object, ok := group.(map[string]any); ok && object["name"] == ConnectionGroup {
			groupIndex = index
			break
		}
	}
	if groupIndex >= 0 {
		existing, _ := groups[groupIndex].(map[string]any)
		if kind, _ := existing["type"].(string); !strings.EqualFold(kind, "select") {
			return Result{}, refuse("В подписке уже есть группа с именем "+ConnectionGroup, "group name taken by a non-select group")
		}
		groups[groupIndex] = withEntry(existing, "include-all", true)
	} else {
		groups = append(groups, map[string]any{"name": ConnectionGroup, "type": "select", "include-all": true})
	}
	config["proxy-groups"] = groups

	// Route everything entering the local listener through the selected node.
	config["mode"] = "rule"
	config["rules"] = []string{"MATCH," + ConnectionGroup}

	out, err := yaml.Marshal(config)
	if err != nil {
		return Result{}, refuse("Не удалось обработать подписку", err.Error())
	}
	return Result{YAML: string(out), Servers: servers(config), Skipped: skipped}, nil
}

func withEntry(existing any, key string, value any) map[string]any {
	out := map[string]any{}
	if object, ok := existing.(map[string]any); ok {
		for k, v := range object {
			out[k] = v
		}
	}
	out[key] = value
	return out
}

func servers(config map[string]any) []Server {
	list, _ := config["proxies"].([]any)
	out := make([]Server, 0, len(list))
	for _, item := range list {
		object, ok := item.(map[string]any)
		if !ok {
			continue
		}
		out = append(out, Server{
			Name:   text(object["name"]),
			Type:   text(object["type"]),
			Server: text(object["server"]),
			Port:   intValue(object["port"]),
		})
	}
	return out
}

// parseObject reads a YAML document. Duplicate keys and parse errors are refusals, as on Android.
func parseObject(source string) (map[string]any, bool) {
	var value any
	if err := yaml.Unmarshal([]byte(source), &value); err != nil {
		return nil, false
	}
	object, ok := value.(map[string]any)
	return object, ok
}

func decodeBase64Document(source string) (string, bool) {
	compact := strings.Join(strings.Fields(source), "")
	if len(compact) < minBase64Length || len(compact)%4 == 1 || !base64Document.MatchString(compact) {
		return "", false
	}
	padded := compact + strings.Repeat("=", (4-len(compact)%4)%4)
	encoding := base64.StdEncoding
	if strings.ContainsAny(compact, "-_") {
		encoding = base64.URLEncoding
	}
	bytes, err := encoding.DecodeString(padded)
	if err != nil || len(bytes) == 0 || len(bytes) > MaxProfileBytes {
		return "", false
	}
	if !utf8.Valid(bytes) {
		return "", false
	}
	decoded := strings.TrimSpace(strings.TrimPrefix(string(bytes), "\uFEFF"))
	if decoded == "" || strings.ContainsRune(decoded, 0) {
		return "", false
	}
	return decoded, true
}

type uriList struct {
	proxies []any
	skipped int
}

// parseURIList converts common subscription URI formats to Mihomo proxy objects.
func parseURIList(source string) uriList {
	normalized := strings.NewReplacer("\r\n", "\n", "\r", "\n").Replace(source)
	var list uriList
	for _, raw := range strings.Split(normalized, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if proxy := parseURI(line); proxy != nil {
			list.proxies = append(list.proxies, proxy)
		} else {
			list.skipped++
		}
	}
	return list
}

func parseURI(line string) map[string]any {
	if len(line) >= len("vmess://") && strings.EqualFold(line[:len("vmess://")], "vmess://") {
		return parseVmess(line[len("vmess://"):])
	}
	u, err := url.Parse(line)
	if err != nil || u.Scheme == "" {
		return nil
	}
	host := u.Hostname()
	port, err := strconv.Atoi(u.Port())
	if host == "" || err != nil || port < 1 || port > 65535 {
		return nil
	}
	scheme := strings.ToLower(u.Scheme)
	name := u.Fragment
	if strings.TrimSpace(name) == "" {
		name = scheme + "-" + host + "-" + strconv.Itoa(port)
	}
	params := parseQuery(u.RawQuery)
	proxy := map[string]any{"name": truncateRunes(name, maxNameRunes), "server": host, "port": port}

	switch scheme {
	case "ss":
		proxy["type"] = "ss"
		decoded := userInfo(u)
		if decoded == "" {
			return nil
		}
		methodPassword := decoded
		if !strings.Contains(decoded, ":") {
			plain, ok := decodeBase64Text(decoded)
			if !ok {
				return nil
			}
			methodPassword = plain
		}
		split := strings.Index(methodPassword, ":")
		if split <= 0 || split == len(methodPassword)-1 {
			return nil
		}
		proxy["cipher"] = methodPassword[:split]
		proxy["password"] = methodPassword[split+1:]
		if plugin, ok := params["plugin"]; ok {
			proxy["plugin"] = plugin
		}
	case "trojan":
		proxy["type"] = "trojan"
		password := userInfo(u)
		if strings.TrimSpace(password) == "" {
			return nil
		}
		proxy["password"] = password
		addTLS(proxy, params, host)
		if _, ok := proxy["tls"]; !ok {
			// Trojan is always TLS. Android sets TLS only with security=tls, which drops the SNI of most links.
			servername, found := firstOf(params, "sni", "peer")
			if !found {
				servername = host
			}
			proxy["tls"] = true
			proxy["servername"] = servername
		}
	case "vless":
		proxy["type"] = "vless"
		id := userInfo(u)
		if strings.TrimSpace(id) == "" {
			return nil
		}
		proxy["uuid"] = id
		addTransport(proxy, params, host)
		addTLS(proxy, params, host)
		if flow, ok := params["flow"]; ok {
			proxy["flow"] = flow
		}
		if encryption, ok := params["encryption"]; ok {
			proxy["encryption"] = encryption
		}
		if udp, ok := params["udp"]; ok && isTrue(udp) {
			proxy["udp"] = true
		}
		if value, ok := firstOf(params, "packetEncoding", "packet-encoding"); ok {
			proxy["packet-encoding"] = value
		}
		if value, ok := firstOf(params, "fp", "fingerprint"); ok {
			proxy["client-fingerprint"] = value
		}
		if value, ok := firstOf(params, "allowInsecure", "insecure"); ok && isTrue(value) {
			proxy["skip-cert-verify"] = true
		}
	case "hysteria2", "hy2":
		proxy["type"] = "hysteria2"
		raw := userInfo(u)
		password := raw
		if index := strings.Index(raw, ":"); index >= 0 {
			password = raw[index+1:]
		}
		if strings.TrimSpace(password) == "" {
			return nil
		}
		proxy["password"] = password
		addTLS(proxy, params, host)
		if value, ok := params["obfs"]; ok {
			proxy["obfs"] = value
		}
		if value, ok := params["obfs-password"]; ok {
			proxy["obfs-password"] = value
		}
		if value, ok := params["sni"]; ok {
			proxy["sni"] = value
		}
	case "tuic":
		proxy["type"] = "tuic"
		credentials := strings.SplitN(userInfo(u), ":", 2)
		if len(credentials) != 2 {
			return nil
		}
		proxy["uuid"] = credentials[0]
		proxy["password"] = credentials[1]
		addTLS(proxy, params, host)
		if value, ok := params["congestion_control"]; ok {
			proxy["congestion-controller"] = value
		}
		if value, ok := params["alpn"]; ok {
			proxy["alpn"] = strings.Split(value, ",")
		}
	default:
		return nil
	}
	return proxy
}

func parseVmess(encoded string) map[string]any {
	plain, ok := decodeBase64Text(encoded)
	if !ok {
		return nil
	}
	var fields map[string]any
	if err := json.Unmarshal([]byte(plain), &fields); err != nil || fields == nil {
		return nil
	}
	host := field(fields, "add")
	port, _ := strconv.Atoi(field(fields, "port"))
	uuid := field(fields, "id")
	if strings.TrimSpace(host) == "" || port < 1 || port > 65535 || strings.TrimSpace(uuid) == "" {
		return nil
	}
	name := field(fields, "ps")
	if strings.TrimSpace(name) == "" {
		name = "vmess-" + host + "-" + strconv.Itoa(port)
	}
	alterID, err := strconv.Atoi(valueOr(fields, "aid", "0"))
	if err != nil {
		alterID = 0
	}
	proxy := map[string]any{
		"name": truncateRunes(name, maxNameRunes), "type": "vmess", "server": host, "port": port,
		"uuid": uuid, "alterId": alterID, "cipher": "auto",
	}
	if strings.EqualFold(field(fields, "tls"), "tls") {
		proxy["tls"] = true
		servername := field(fields, "sni")
		if strings.TrimSpace(servername) == "" {
			servername = field(fields, "host")
		}
		if strings.TrimSpace(servername) == "" {
			servername = host
		}
		proxy["servername"] = servername
		if alpn := field(fields, "alpn"); strings.TrimSpace(alpn) != "" {
			proxy["alpn"] = strings.Split(alpn, ",")
		}
	}
	switch strings.ToLower(field(fields, "net")) {
	case "ws":
		path := "/"
		if hasField(fields, "path") {
			path = field(fields, "path")
		}
		proxy["ws-opts"] = map[string]any{"path": path, "headers": map[string]any{"Host": field(fields, "host")}}
	case "grpc":
		proxy["grpc-opts"] = map[string]any{"grpc-service-name": field(fields, "path")}
	case "tcp", "":
		// Plain TCP has no extra options.
	default:
		return nil
	}
	return proxy
}

func addTLS(proxy map[string]any, params map[string]string, host string) {
	security := strings.ToLower(params["security"])
	tlsOn := security == "tls" || security == "reality" || isTrue(params["tls"])
	if !tlsOn {
		return
	}
	proxy["tls"] = true
	servername, ok := firstOf(params, "sni", "serverName", "peer")
	if !ok {
		servername = host
	}
	proxy["servername"] = servername
	if alpn, ok := params["alpn"]; ok {
		proxy["alpn"] = strings.Split(alpn, ",")
	}
	if security == "reality" {
		reality := map[string]any{}
		if key, ok := firstOf(params, "pbk", "publicKey"); ok {
			reality["public-key"] = key
		}
		if shortID, ok := firstOf(params, "sid", "shortId"); ok {
			reality["short-id"] = shortID
		}
		proxy["reality-opts"] = reality
		if value, ok := firstOf(params, "fp", "fingerprint"); ok {
			proxy["client-fingerprint"] = value
		}
	}
}

func addTransport(proxy map[string]any, params map[string]string, host string) {
	network := strings.ToLower(valueOrFirst(params, "tcp", "type", "network"))
	switch network {
	case "ws", "http", "h2", "grpc", "xhttp":
		proxy["network"] = network
	default:
		proxy["network"] = "tcp"
	}
	switch network {
	case "ws":
		opts := map[string]any{"path": valueOrFirst(params, "/", "path")}
		if value, ok := params["host"]; ok {
			opts["headers"] = map[string]any{"Host": value}
		}
		proxy["ws-opts"] = opts
	case "grpc":
		proxy["grpc-opts"] = map[string]any{"grpc-service-name": valueOrFirst(params, "", "serviceName", "service_name", "path")}
	case "http":
		opts := map[string]any{"path": []string{valueOrFirst(params, "/", "path")}}
		if value, ok := params["host"]; ok {
			opts["headers"] = map[string]any{"Host": []string{value}}
		}
		proxy["http-opts"] = opts
	case "h2":
		opts := map[string]any{"path": valueOrFirst(params, "/", "path")}
		if value, ok := params["host"]; ok {
			opts["host"] = nonEmptyTrimmed(strings.Split(value, ","))
		}
		proxy["h2-opts"] = opts
	case "xhttp":
		proxy["xhttp-opts"] = xhttpOptions(params)
	}
}

// xhttpMappings maps the app's query keys to the Mihomo option names, in the Android order.
var xhttpMappings = []struct{ source, key, kind string }{
	{"noGrpcHeader", "no-grpc-header", "bool"},
	{"xPaddingBytes", "x-padding-bytes", "string"},
	{"xPaddingObfsMode", "x-padding-obfs-mode", "bool"},
	{"xPaddingKey", "x-padding-key", "string"},
	{"xPaddingHeader", "x-padding-header", "string"},
	{"xPaddingPlacement", "x-padding-placement", "string"},
	{"xPaddingMethod", "x-padding-method", "string"},
	{"uplinkHTTPMethod", "uplink-http-method", "string"},
	{"sessionPlacement", "session-placement", "string"},
	{"sessionKey", "session-key", "string"},
	{"sessionTable", "session-table", "string"},
	{"sessionLength", "session-length", "int"},
	{"seqPlacement", "seq-placement", "string"},
	{"seqKey", "seq-key", "string"},
	{"uplinkDataPlacement", "uplink-data-placement", "string"},
	{"uplinkDataKey", "uplink-data-key", "string"},
	{"uplinkChunkSize", "uplink-chunk-size", "int"},
	{"scMaxEachPostBytes", "sc-max-each-post-bytes", "int"},
	{"scMinPostsIntervalMs", "sc-min-posts-interval-ms", "int"},
}

func xhttpOptions(params map[string]string) map[string]any {
	opts := map[string]any{
		"path": valueOrFirst(params, "/", "path"),
		"mode": valueOrFirst(params, "auto", "mode"),
	}
	if value, ok := params["host"]; ok {
		opts["host"] = value
	}
	for _, mapping := range xhttpMappings {
		value, ok := params[mapping.source]
		if !ok {
			continue
		}
		switch mapping.kind {
		case "bool":
			opts[mapping.key] = isTrue(value)
		case "int":
			if number, err := strconv.Atoi(value); err == nil {
				opts[mapping.key] = number
			} else {
				opts[mapping.key] = value
			}
		default:
			opts[mapping.key] = value
		}
	}
	if value, ok := params["headers"]; ok {
		headers := map[string]any{}
		for _, header := range strings.Split(value, ",") {
			index := strings.Index(header, ":")
			if index <= 0 {
				continue
			}
			headers[strings.TrimSpace(header[:index])] = strings.TrimSpace(header[index+1:])
		}
		if len(headers) > 0 {
			opts["headers"] = headers
		}
	}
	return opts
}

// userInfo returns the decoded user part of a URI, or "" when there is none.
func userInfo(u *url.URL) string {
	if u.User == nil {
		return ""
	}
	return decodePart(u.User.String())
}

// decodePart decodes percent escapes. A literal "+" stays "+", as on Android.
func decodePart(value string) string {
	decoded, err := url.PathUnescape(strings.ReplaceAll(value, "+", "%2B"))
	if err != nil {
		return value
	}
	return decoded
}

// parseQuery reads a query string. A repeated key keeps its last value, as on Android.
func parseQuery(raw string) map[string]string {
	params := map[string]string{}
	for _, item := range strings.Split(raw, "&") {
		if strings.TrimSpace(item) == "" {
			continue
		}
		key, value, _ := strings.Cut(item, "=")
		params[decodePart(key)] = decodePart(value)
	}
	return params
}

func decodeBase64Text(value string) (string, bool) {
	compact := strings.NewReplacer("-", "+", "_", "/").Replace(strings.TrimSpace(value))
	compact += strings.Repeat("=", (4-len(compact)%4)%4)
	decoded, err := base64.StdEncoding.DecodeString(compact)
	if err != nil {
		return "", false
	}
	return string(decoded), true
}

func isTrue(value string) bool {
	return strings.EqualFold(value, "true") || value == "1"
}

// firstOf returns the value of the first key that is present, even when empty.
func firstOf(params map[string]string, keys ...string) (string, bool) {
	for _, key := range keys {
		if value, ok := params[key]; ok {
			return value, true
		}
	}
	return "", false
}

func valueOrFirst(params map[string]string, fallback string, keys ...string) string {
	if value, ok := firstOf(params, keys...); ok {
		return value
	}
	return fallback
}

func field(fields map[string]any, key string) string {
	return text(fields[key])
}

func hasField(fields map[string]any, key string) bool {
	_, ok := fields[key]
	return ok
}

func valueOr(fields map[string]any, key, fallback string) string {
	if !hasField(fields, key) {
		return fallback
	}
	return field(fields, key)
}

func nonEmptyTrimmed(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func truncateRunes(value string, limit int) string {
	runes := []rune(value)
	if len(runes) <= limit {
		return value
	}
	return string(runes[:limit])
}

func text(value any) string {
	switch typed := value.(type) {
	case nil:
		return ""
	case string:
		return typed
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	default:
		return fmt.Sprint(typed)
	}
}

func intValue(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case float64:
		return int(typed)
	case string:
		number, _ := strconv.Atoi(typed)
		return number
	default:
		return 0
	}
}
