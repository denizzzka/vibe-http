#!/bin/bash

set -e -o pipefail

# The proxy tests require external proxy servers. They are installed by the CI
# workflow and are not available on all platforms.
if ! command -v microsocks >/dev/null 2>&1; then
	echo "SKIPPING proxy tests (microsocks is not installed)"
	exit 0
fi

SOCKS5_PORT=1080
SOCKS5_AUTH_PORT=1081
PROXY_USER=testuser
PROXY_PASS=testpass

PIDS=()
cleanup() {
	for pid in "${PIDS[@]}"; do
		kill "$pid" 2>/dev/null
	done
	return 0
}
trap cleanup EXIT

microsocks -p $SOCKS5_PORT &
PIDS+=($!)
microsocks -p $SOCKS5_AUTH_PORT -u $PROXY_USER -P $PROXY_PASS &
PIDS+=($!)

# wait until a port accepts connections
wait_port() {
	for _ in {1..50}; do
		(echo > /dev/tcp/127.0.0.1/$1) 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

wait_port $SOCKS5_PORT || { echo "microsocks failed to start on port $SOCKS5_PORT" >&2; exit 1; }
wait_port $SOCKS5_AUTH_PORT || { echo "microsocks failed to start on port $SOCKS5_AUTH_PORT" >&2; exit 1; }

export PROXY_SOCKS5="socks5://127.0.0.1:$SOCKS5_PORT"
export PROXY_SOCKS5_AUTH="socks5://$PROXY_USER:$PROXY_PASS@127.0.0.1:$SOCKS5_AUTH_PORT"

echo "Running HTTP client proxy tests"

dub build --compiler=${DC:-dmd} 2>&1

./tests

echo "OK"
