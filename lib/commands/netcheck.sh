# shellcheck shell=bash
# lib/commands/netcheck.sh — `meister netcheck`: read-only network path check.
#
# One fixed method, so runs are comparable:
#   1. gateway ping series (NETCHECK_PINGS, default 100, 0.2 s apart)
#      → p95 (nearest rank), jitter (mean |Δ| of consecutive RTTs),
#        share of sent pings above 20 ms, loss
#   2. networkQuality -c runs (NETCHECK_NQ_RUNS, default 3, max 20 s each)
#      → median download / upload Mbit/s and responsiveness RPM
# The verdict names AWDL only when Wi-Fi is primary, awdl0 is UP and the pings
# spike (p95 > 20 ms or >= 10 % of pings above 20 ms). Each full run is stored
# as JSON under $MEISTER_DIR/netcheck/ (latest.json = baseline for the next
# run's before/after table). --quick: 20 pings + 1 networkQuality run, never
# written. Changes nothing on the system; no sudo. Bash 3.2 compatible.

NETCHECK_SPIKE_MS=20

# route -n get default → "gateway iface" (empty when there is no default route)
_netcheck_route() {
    route -n get default 2>/dev/null | awk '
        $1 == "gateway:"   { gw = $2 }
        $1 == "interface:" { ifc = $2 }
        END { if (ifc != "") print (gw == "" ? "-" : gw), ifc }'
}

# networksetup -listallhardwareports → "port<TAB>device" lines
_netcheck_ports() {
    networksetup -listallhardwareports 2>/dev/null | awk '
        /^Hardware Port: / { sub(/^Hardware Port: /, ""); port = $0 }
        /^Device: /        { sub(/^Device: /, ""); if (port != "") print port "\t" $0; port = "" }'
}

_netcheck_iface_type() { # iface ports
    local port
    port=$(printf '%s\n' "$2" | awk -F '\t' -v d="$1" '$2 == d { print $1; exit }')
    case "$port" in
        Wi-Fi|AirPort) echo wifi ;;
        *Ethernet*|*LAN*|*Thunderbolt*) echo ethernet ;;
        *) echo other ;;
    esac
}

_netcheck_awdl() {
    local out
    out=$(ifconfig awdl0 2>/dev/null) || { echo absent; return; }
    [ -n "$out" ] || { echo absent; return; }
    if printf '%s\n' "$out" | head -1 | grep -Eq '[<,]UP[,>]'; then echo up; else echo down; fi
}

# Devices of ports named exactly "Ethernet" without a cable (status: inactive).
_netcheck_idle_ethernet() { # ports
    local dev
    printf '%s\n' "$1" | awk -F '\t' '$1 == "Ethernet" { print $2 }' | while read -r dev; do
        [ -n "$dev" ] || continue
        ifconfig "$dev" 2>/dev/null | grep -Eq '^[[:space:]]*status: inactive' && echo "$dev"
    done
}

# ping output on stdin → "p95 jitter over20 loss received" (null when unknown)
_netcheck_ping_stats() { # requested_count
    python3 -c '
import math, re, sys
requested = int(sys.argv[1])
rtts, sent = [], None
for line in sys.stdin:
    m = re.search(r"time[=<]([0-9.]+) ?ms", line)
    if m:
        rtts.append(float(m.group(1)))
    m = re.search(r"([0-9]+) packets transmitted", line)
    if m:
        sent = int(m.group(1))
sent = sent or requested
if not rtts:
    print("null null 0.0 100.0 0")
    sys.exit(0)
s = sorted(rtts)
p95 = s[max(0, math.ceil(0.95 * len(s)) - 1)]
jit = sum(abs(b - a) for a, b in zip(rtts, rtts[1:])) / (len(rtts) - 1) if len(rtts) > 1 else 0.0
over = sum(1 for r in rtts if r > float(sys.argv[2])) * 100.0 / sent
loss = max(0.0, (sent - len(rtts)) * 100.0 / sent)
print("%.1f %.1f %.1f %.1f %d" % (p95, jit, over, loss, len(rtts)))
' "$1" "$NETCHECK_SPIKE_MS"
}

# networkQuality JSON objects, one per line, on stdin → "dl_mbps ul_mbps rpm" medians
_netcheck_nq_stats() {
    python3 -c '
import json, sys
cols = {"dl_throughput": [], "ul_throughput": [], "responsiveness": []}
for line in sys.stdin:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if not isinstance(d, dict):
        continue
    for k, vals in cols.items():
        v = d.get(k)
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            vals.append(float(v))
def median(v):
    if not v:
        return None
    v = sorted(v)
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2
dl, ul, rpm = (median(cols[k]) for k in ("dl_throughput", "ul_throughput", "responsiveness"))
print(" ".join([
    "null" if dl is None else "%.1f" % (dl / 1e6),
    "null" if ul is None else "%.1f" % (ul / 1e6),
    "null" if rpm is None else "%d" % round(rpm),
]))
'
}

# netcheck_verdict iface_type awdl p95_ms over20_pct received
netcheck_verdict() {
    local type="$1" awdl="$2" p95="$3" over="$4" received="${5:-0}" spikes
    if [ "$received" = 0 ] || [ "$p95" = null ]; then echo no_gateway_reply; return; fi
    spikes=$(awk -v p="$p95" -v o="$over" -v t="$NETCHECK_SPIKE_MS" \
        'BEGIN { print ((p + 0 > t || o + 0 >= 10) ? 1 : 0) }')
    if [ "$type" = wifi ]; then
        if [ "$spikes" = 0 ]; then echo ok
        elif [ "$awdl" = up ]; then echo awdl_spikes
        else echo wifi_spikes
        fi
    elif [ "$spikes" = 0 ]; then echo ok_wired
    else echo wired_spikes
    fi
}

# netcheck_measure [--quick] → one JSON object on stdout; exit 2 without default route.
netcheck_measure() {
    local quick=false pings="${NETCHECK_PINGS:-100}" runs="${NETCHECK_NQ_RUNS:-3}" secs=20
    [ "${1:-}" = --quick ] && { quick=true; pings=20; runs=1; secs=10; }
    local route gateway iface ports type awdl idle ping_out nq_out i verdict
    route=$(_netcheck_route)
    [ -n "$route" ] || return 2
    gateway=${route%% *}
    iface=${route#* }
    ports=$(_netcheck_ports)
    type=$(_netcheck_iface_type "$iface" "$ports")
    awdl=$(_netcheck_awdl)
    idle=$(_netcheck_idle_ethernet "$ports")

    local p95=null jitter=null over20=0.0 loss=100.0 received=0
    if [ "$gateway" != - ]; then
        # -t: overall deadline on macOS so a silent gateway cannot hang the run
        ping_out=$(ping -n -c "$pings" -i 0.2 -t $((pings / 5 + 5)) "$gateway" 2>/dev/null)
        # shellcheck disable=SC2034
        read -r p95 jitter over20 loss received <<EOF
$(printf '%s\n' "$ping_out" | _netcheck_ping_stats "$pings")
EOF
    fi

    nq_out=""
    if command -v networkQuality >/dev/null 2>&1; then
        i=0
        while [ "$i" -lt "$runs" ]; do
            nq_out="$nq_out$(networkQuality -c -M "$secs" 2>/dev/null | tr -d '\n')
"
            i=$((i + 1))
        done
    fi
    local dl=null ul=null rpm=null
    read -r dl ul rpm <<EOF
$(printf '%s' "$nq_out" | _netcheck_nq_stats)
EOF
    verdict=$(netcheck_verdict "$type" "$awdl" "$p95" "$over20" "$received")

    python3 -c '
import json, sys, time
a = sys.argv[1:]
num = lambda s: None if s == "null" else (int(s) if s.isdigit() else float(s))
print(json.dumps({
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "interface": a[0], "interface_type": a[1],
    "gateway": None if a[2] == "-" else a[2], "awdl": a[3],
    "ping_p95_ms": num(a[4]), "jitter_ms": num(a[5]),
    "over20_pct": num(a[6]), "loss_pct": num(a[7]),
    "dl_mbps": num(a[8]), "ul_mbps": num(a[9]), "rpm": num(a[10]),
    "verdict": a[11],
    "idle_ethernet": [d for d in a[12].split("\n") if d],
}, indent=2))
' "$iface" "$type" "$gateway" "$awdl" "$p95" "$jitter" "$over20" "$loss" \
      "$dl" "$ul" "$rpm" "$verdict" "$idle"
}

# Table now (and previous when readable) + verdict lines. Args: now_json prev_file cmd
_netcheck_render() {
    python3 -c '
import json, sys
now = json.loads(sys.argv[1])
prev, prev_file, cmd = None, sys.argv[2], sys.argv[3]
if prev_file:
    try:
        with open(prev_file) as f:
            prev = json.load(f)
        if not isinstance(prev, dict):
            raise ValueError
    except (OSError, ValueError):
        prev = None
        print("  previous result unreadable")
ifc_label = {"wifi": "Wi-Fi", "ethernet": "Ethernet"}.get(now["interface_type"], now["interface_type"])
print("  gateway %s via %s (%s), AWDL: %s" % (now["gateway"] or "?", now["interface"], ifc_label, now["awdl"]))
rows = [("Download, median", "dl_mbps", "Mbit/s", "%.0f"), ("Upload, median", "ul_mbps", "Mbit/s", "%.0f"),
        ("Responsiveness", "rpm", "RPM", "%.0f"), ("Gateway ping p95", "ping_p95_ms", "ms", "%.1f"),
        ("Jitter", "jitter_ms", "ms", "%.1f"), ("Pings over 20 ms", "over20_pct", "%", "%.0f"),
        ("Ping loss", "loss_pct", "%", "%.0f")]
def cell(d, key, unit, fmt):
    v = d.get(key) if isinstance(d, dict) else None
    return "n/a" if not isinstance(v, (int, float)) else (fmt % v) + " " + unit
if prev is not None:
    print("  %-18s  %-12s  %s" % ("", "previous", "now"))
for label, key, unit, fmt in rows:
    if prev is not None:
        print("  %-18s  %-12s  %s" % (label, cell(prev, key, unit, fmt), cell(now, key, unit, fmt)))
    else:
        print("  %-18s  %s" % (label, cell(now, key, unit, fmt)))
print("")
v = now["verdict"]
msg = {
    "awdl_spikes": "Likely cause: AWDL latency spikes on Wi-Fi",
    "wifi_spikes": "Cause unknown: Wi-Fi latency spikes",
    "ok": "OK: no latency spikes on Wi-Fi",
    "ok_wired": "OK: wired connection without latency spikes",
    "wired_spikes": "Latency spikes on the wired connection (router or LAN)",
    "no_gateway_reply": "No reply from gateway %s" % (now["gateway"] or "?"),
}[v]
print("  " + msg)
idle = now.get("idle_ethernet") or []
if now["interface_type"] == "wifi" and idle:
    print("  Fix: connect a LAN cable to %s" % idle[0])
if (now["interface_type"] == "wifi" and idle) or v == "awdl_spikes":
    print("  Fallback: %s awdl guard on — AirDrop, AirPlay, Handoff, Universal Control and Apple Watch unlock stop working" % cmd)
' "$1" "$2" "$3"
}

_netcheck_usage() {
    cat <<'USAGE'
    (no flags)   Gateway ping series + 3 networkQuality runs (~80 s), verdict,
                 before/after table; result saved as the next baseline
    --quick      20 pings + 1 networkQuality run (~15 s), not saved
USAGE
}

cmd_netcheck() {
    local quick="" arg
    for arg in "$@"; do
        case "$arg" in
            --quick) quick=--quick ;;
            -h|--help) _netcheck_usage; return 0 ;;
            *) echo "  Unknown option: $arg"; _netcheck_usage; return 2 ;;
        esac
    done
    local dir="$MEISTER_DIR/netcheck" now rc prev="" stamp
    if [ -z "$quick" ]; then
        echo "  Measuring: ${NETCHECK_PINGS:-100} gateway pings + ${NETCHECK_NQ_RUNS:-3} networkQuality runs (about 80 s)…"
    else
        echo "  Measuring (quick): 20 gateway pings + 1 networkQuality run…"
    fi
    now=$(netcheck_measure $quick)
    rc=$?
    if [ "$rc" = 2 ]; then echo "  No network connection (no default route)"; return 2; fi
    [ "$rc" = 0 ] && [ -n "$now" ] || { echo "  netcheck: measurement failed"; return 1; }
    [ -e "$dir/latest.json" ] && prev="$dir/latest.json"
    _netcheck_render "$now" "$prev" "${NETCHECK_CMD:-MeisterAI}"
    [ -z "$quick" ] || return 0
    mkdir -p "$dir" || return 1
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    printf '%s\n' "$now" > "$dir/$stamp.json" &&
        cp "$dir/$stamp.json" "$dir/latest.json.tmp" &&
        mv -f "$dir/latest.json.tmp" "$dir/latest.json"
    echo ""
    echo "  Saved: $dir/latest.json"
}
