#!/usr/bin/env bats
# meister netcheck — gateway ping series + networkQuality, AWDL verdict, before/after.
# route, networksetup, ifconfig, ping and networkQuality are stubbed as shell
# functions; nothing here touches the real network.

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/.meister"
  mkdir -p "$MEISTER_DIR"
  source "$BATS_TEST_DIRNAME/../lib/commands/netcheck.sh"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  : > "$STUB/nq_count"
  # defaults: Wi-Fi en1 primary, AWDL up, en0 Ethernet without cable, 5 ms pings
  NC_IFACE=en1
  NC_AWDL=up
  NC_EN0_STATUS=inactive
  NC_EXTRA_PORTS=""
  NC_RTTS="$(rtts_const 100 5.0)"
  NC_NQ_FAIL=0
  printf '%s\n' \
    '{"dl_throughput":429000000,"ul_throughput":87000000,"responsiveness":485,"interface_name":"en1"}' \
    '{"dl_throughput":450000000,"ul_throughput":46000000,"responsiveness":597,"interface_name":"en1"}' \
    '{"dl_throughput":644000000,"ul_throughput":108000000,"responsiveness":1059,"interface_name":"en1"}' \
    > "$STUB/nq_results"

  route() {
    if [ -z "$NC_IFACE" ]; then
      echo "route: writing to routing socket: not in table" >&2
      return 1
    fi
    printf '   route to: default\ndestination: default\n'
    [ "${NC_GW-192.168.178.1}" = "" ] || printf '    gateway: %s\n' "${NC_GW-192.168.178.1}"
    printf '  interface: %s\n' "$NC_IFACE"
  }
  networksetup() {
    printf '\nHardware Port: Ethernet\nDevice: en0\nEthernet Address: aa:bb:cc:dd:ee:00\n'
    printf '\nHardware Port: Wi-Fi\nDevice: en1\nEthernet Address: aa:bb:cc:dd:ee:01\n'
    printf '\nHardware Port: Thunderbolt Bridge\nDevice: bridge0\nEthernet Address: N/A\n'
    [ -n "$NC_EXTRA_PORTS" ] && printf '%b' "$NC_EXTRA_PORTS"
    return 0
  }
  ifconfig() {
    case "$1" in
      awdl0)
        case "$NC_AWDL" in
          up) echo "awdl0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500" ;;
          down) echo "awdl0: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500" ;;
          *) echo "ifconfig: interface awdl0 does not exist" >&2; return 1 ;;
        esac ;;
      en0) printf 'en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n\tstatus: %s\n' "$NC_EN0_STATUS" ;;
      en5) printf 'en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n\tstatus: inactive\n' ;;
      bridge0) printf 'bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n\tstatus: inactive\n' ;;
      *) printf '%s: flags=8863<UP,RUNNING> mtu 1500\n\tstatus: active\n' "$1" ;;
    esac
  }
  ping() {
    local seq=0 rtt sent=0
    for rtt in $NC_RTTS; do
      sent=$((sent + 1))
      [ "$rtt" = x ] && continue
      echo "64 bytes from 192.168.178.1: icmp_seq=$seq ttl=64 time=$rtt ms"
      seq=$((seq + 1))
    done
    echo "--- 192.168.178.1 ping statistics ---"
    echo "$sent packets transmitted, $seq packets received"
    [ "$seq" -gt 0 ]
  }
  networkQuality() {
    echo x >> "$STUB/nq_count"
    [ "$NC_NQ_FAIL" = 1 ] && return 1
    sed -n "$(wc -l < "$STUB/nq_count" | tr -d ' ')p" "$STUB/nq_results"
  }
}

rtts_const() { # count value
  local i=0 out=""
  while [ "$i" -lt "$1" ]; do out="$out $2"; i=$((i + 1)); done
  echo "$out"
}

rtts_spiky() { # 85 x 5 ms + 15 x 65 ms
  echo "$(rtts_const 85 5.0) $(rtts_const 15 65.0)"
}

json_get() { # json key
  printf '%s' "$1" | python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print("null" if v is None else v)' "$2"
}

@test "computes p95 jitter share and medians from ping and networkQuality" {
  NC_RTTS="$(seq 1 100 | sed 's/$/.0/' | tr '\n' ' ')"
  run netcheck_measure
  [ "$status" = 0 ]
  [ "$(json_get "$output" ping_p95_ms)" = 95.0 ]
  [ "$(json_get "$output" jitter_ms)" = 1.0 ]
  [ "$(json_get "$output" over20_pct)" = 80.0 ]
  [ "$(json_get "$output" loss_pct)" = 0.0 ]
  [ "$(json_get "$output" dl_mbps)" = 450.0 ]
  [ "$(json_get "$output" ul_mbps)" = 87.0 ]
  [ "$(json_get "$output" rpm)" = 597 ]
  [ "$(json_get "$output" interface)" = en1 ]
  [ "$(json_get "$output" interface_type)" = wifi ]
  [ "$(json_get "$output" gateway)" = 192.168.178.1 ]
  [ "$(json_get "$output" awdl)" = up ]
  [ "$(wc -l < "$STUB/nq_count" | tr -d ' ')" = 3 ]
}

@test "verdict awdl_spikes on Wi-Fi with AWDL up and spikes" {
  NC_RTTS="$(rtts_spiky)"
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"Likely cause: AWDL latency spikes on Wi-Fi"* ]]
  grep -q '"verdict": "awdl_spikes"' "$MEISTER_DIR/netcheck/latest.json"
}

@test "verdict wifi_spikes on Wi-Fi with AWDL down and spikes" {
  NC_RTTS="$(rtts_spiky)"
  NC_AWDL=down
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"Cause unknown: Wi-Fi latency spikes"* ]]
  [[ "$output" != *"Likely cause: AWDL"* ]]
  grep -q '"verdict": "wifi_spikes"' "$MEISTER_DIR/netcheck/latest.json"
}

@test "verdict ok on Wi-Fi with AWDL up and flat 5 ms pings" {
  run netcheck_measure
  [ "$status" = 0 ]
  [ "$(json_get "$output" verdict)" = ok ]
}

@test "verdict ok_wired and wired_spikes on Ethernet, no AWDL line" {
  NC_IFACE=en0
  NC_EN0_STATUS=active
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" != *"AWDL latency"* ]]
  grep -q '"verdict": "ok_wired"' "$MEISTER_DIR/netcheck/latest.json"
  grep -q '"interface_type": "ethernet"' "$MEISTER_DIR/netcheck/latest.json"
  NC_RTTS="$(rtts_spiky)"
  run netcheck_measure
  [ "$(json_get "$output" verdict)" = wired_spikes ]
}

@test "verdict with awdl0 absent does not crash" {
  NC_AWDL=absent
  NC_RTTS="$(rtts_spiky)"
  run netcheck_measure
  [ "$status" = 0 ]
  [ "$(json_get "$output" awdl)" = absent ]
  [ "$(json_get "$output" verdict)" = wifi_spikes ]
}

@test "verdict unit: thresholds p95 above 20 ms or at least 10 percent over 20 ms" {
  [ "$(netcheck_verdict wifi up 20.0 9.9 100)" = ok ]
  [ "$(netcheck_verdict wifi up 20.1 0 100)" = awdl_spikes ]
  [ "$(netcheck_verdict wifi up 8.0 10.0 100)" = awdl_spikes ]
  [ "$(netcheck_verdict wifi down 8.0 10.0 100)" = wifi_spikes ]
  [ "$(netcheck_verdict ethernet up 8.0 1.0 100)" = ok_wired ]
  [ "$(netcheck_verdict ethernet up 30.0 1.0 100)" = wired_spikes ]
  [ "$(netcheck_verdict wifi up null 0 0)" = no_gateway_reply ]
}

@test "recommends ethernet port en0 when idle and never Ethernet Adapter or Thunderbolt Bridge" {
  NC_RTTS="$(rtts_spiky)"
  NC_EXTRA_PORTS='\nHardware Port: Ethernet Adapter (en5)\nDevice: en5\nEthernet Address: aa:bb:cc:dd:ee:05\n'
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"Fix: connect a LAN cable to en0"* ]]
  [[ "$output" == *"Fallback: MeisterAI awdl guard on — AirDrop, AirPlay, Handoff, Universal Control and Apple Watch unlock stop working"* ]]
  [[ "$output" != *en5* ]]
  [[ "$output" != *bridge0* ]]
  run netcheck_measure
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)["idle_ethernet"]))')" = en0 ]
}

@test "recommends ethernet only when the Ethernet port is inactive" {
  NC_EN0_STATUS=active
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" != *"Fix: connect a LAN cable"* ]]
}

@test "before after table on the second full run" {
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" != *previous* ]]
  [ -f "$MEISTER_DIR/netcheck/latest.json" ]
  ls "$MEISTER_DIR/netcheck" | grep -Eq '^[0-9]{8}T[0-9]{6}Z\.json$'
  : > "$STUB/nq_count"
  NC_RTTS="$(rtts_spiky)"
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *previous*now* ]]
  for label in "Download, median" "Upload, median" "Responsiveness" "Gateway ping p95" "Jitter" "Pings over 20 ms"; do
    [[ "$output" == *"$label"* ]]
  done
  [[ "$output" == *"Mbit/s"* ]]
  [[ "$output" == *"RPM"* ]]
  [[ "$output" == *" ms"* ]]
  [[ "$output" == *" %"* ]]
  grep -q '"verdict": "awdl_spikes"' "$MEISTER_DIR/netcheck/latest.json"
}

@test "before after table: corrupt latest.json reports unreadable and is replaced" {
  mkdir -p "$MEISTER_DIR/netcheck"
  echo '{not json' > "$MEISTER_DIR/netcheck/latest.json"
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"previous result unreadable"* ]]
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$MEISTER_DIR/netcheck/latest.json"
}

@test "before after table: --quick never replaces latest.json" {
  run cmd_netcheck
  [ "$status" = 0 ]
  cp "$MEISTER_DIR/netcheck/latest.json" "$BATS_TEST_TMPDIR/before.json"
  count_before=$(ls "$MEISTER_DIR/netcheck" | wc -l)
  : > "$STUB/nq_count"
  NC_RTTS="$(rtts_spiky)"
  run cmd_netcheck --quick
  [ "$status" = 0 ]
  [[ "$output" == *previous*now* ]]
  cmp -s "$MEISTER_DIR/netcheck/latest.json" "$BATS_TEST_TMPDIR/before.json"
  [ "$(ls "$MEISTER_DIR/netcheck" | wc -l)" = "$count_before" ]
  [ "$(wc -l < "$STUB/nq_count" | tr -d ' ')" = 1 ]
}

@test "failure paths: no default route exits 2" {
  NC_IFACE=""
  run cmd_netcheck
  [ "$status" = 2 ]
  [[ "$output" == *"No network connection"* ]]
  [ ! -f "$MEISTER_DIR/netcheck/latest.json" ]
}

@test "failure paths: networkQuality failing prints n/a, null JSON, exit 0" {
  NC_NQ_FAIL=1
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"Gateway ping p95"* ]]
  [[ "$output" == *"n/a"* ]]
  grep -q '"dl_mbps": null' "$MEISTER_DIR/netcheck/latest.json"
  grep -q '"ul_mbps": null' "$MEISTER_DIR/netcheck/latest.json"
  grep -q '"rpm": null' "$MEISTER_DIR/netcheck/latest.json"
}

@test "failure paths: networkQuality without responsiveness gives rpm n/a" {
  printf '%s\n' '{"dl_throughput":429000000,"ul_throughput":87000000}' > "$STUB/nq_results"
  run cmd_netcheck --quick
  [ "$status" = 0 ]
  [[ "$output" == *"n/a"* ]]
  run netcheck_measure --quick
  [ "$(json_get "$output" rpm)" = null ]
}

@test "failure paths: zero ping replies give no_gateway_reply, never ok" {
  NC_RTTS="$(rtts_const 100 x)"
  run cmd_netcheck
  [ "$status" = 0 ]
  grep -q '"verdict": "no_gateway_reply"' "$MEISTER_DIR/netcheck/latest.json"
  grep -q '"loss_pct": 100.0' "$MEISTER_DIR/netcheck/latest.json"
  [[ "$output" != *"OK:"* ]]
}

@test "recommends ethernet without Fallback line when Wi-Fi has no spikes" {
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"OK: no latency spikes on Wi-Fi"* ]]
  [[ "$output" == *"Fix: connect a LAN cable to en0"* ]]
  [[ "$output" != *"Fallback:"* ]]
}

@test "verdict wifi_spikes prints no Fallback line" {
  NC_RTTS="$(rtts_spiky)"
  NC_AWDL=down
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"Cause unknown: Wi-Fi latency spikes"* ]]
  [[ "$output" != *"Fallback:"* ]]
}

@test "verdict on other interface (utun4) never says wired connection" {
  NC_IFACE=utun4
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"OK: no latency spikes on utun4"* ]]
  [[ "$output" != *"wired connection"* ]]
  grep -q '"interface_type": "other"' "$MEISTER_DIR/netcheck/latest.json"
  grep -q '"verdict": "ok_wired"' "$MEISTER_DIR/netcheck/latest.json"
  NC_RTTS="$(rtts_spiky)"
  run cmd_netcheck
  [[ "$output" == *"Latency spikes on utun4 (VPN/tunnel)"* ]]
  [[ "$output" != *"wired connection"* ]]
  grep -q '"verdict": "wired_spikes"' "$MEISTER_DIR/netcheck/latest.json"
}

@test "failure paths: default route without gateway is not a failure" {
  NC_IFACE=utun4
  NC_GW=""
  : > "$STUB/ping_called"
  ping() { echo called >> "$STUB/ping_called"; return 1; }
  run cmd_netcheck
  [ "$status" = 0 ]
  [[ "$output" == *"no gateway to ping on utun4"* ]]
  [[ "$output" != *"No reply from gateway"* ]]
  [[ "$output" != *"wired connection"* ]]
  [ ! -s "$STUB/ping_called" ]
  run netcheck_measure
  [ "$(json_get "$output" verdict)" = ok_wired ]
  [ "$(json_get "$output" gateway)" = null ]
  [ "$(json_get "$output" ping_p95_ms)" = null ]
  [ "$(json_get "$output" jitter_ms)" = null ]
  [ "$(json_get "$output" over20_pct)" = null ]
  [ "$(json_get "$output" loss_pct)" = null ]
}
