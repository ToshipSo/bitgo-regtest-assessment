#!/bin/bash
set -e

# === CONFIG ===
RPCUSER="admin"
RPCPASSWORD="admin"
REGTEST_OPTS="-regtest -rpcuser=$RPCUSER -rpcpassword=$RPCPASSWORD"

NODE1=node1
NODE2=node2

# === HELP ===
function print_help() {
  echo "Usage: ./script <command> [args...]"
  echo ""
  echo "Available commands:"
  echo "  init                              - Create wallets and connect both nodes"
  echo "  mine <node_name> <blocks>         - Mine specified number of blocks on given node"
  echo "  send <from_node> <to_node> <amt>  - Send BTC from one node to another"
  echo "  balance <node_name>               - Show balance of the node's wallet"
  echo "  full_flow                         - Init, mine 101 blocks, send 10 BTC"
  echo "  help                              - Show this help message"
}

# === INIT ===
function init_nodes() {
  echo "🔧 Creating wallets if missing..."
  docker exec $NODE1 bitcoin-cli $REGTEST_OPTS createwallet "wallet" || true
  docker exec $NODE2 bitcoin-cli $REGTEST_OPTS createwallet "wallet" || true

  echo "🔗 Connecting $NODE1 to $NODE2..."
  docker exec $NODE1 bitcoin-cli $REGTEST_OPTS addnode "$NODE2:18444" "onetry"

  echo "✅ Nodes initialized and connected."
}

# === MINE ===
function mine_blocks() {
  NODE=$1
  BLOCKS=$2
  echo "⛏️ Mining $BLOCKS blocks on $NODE..."
  ADDR=$(docker exec $NODE bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" getnewaddress)
  docker exec $NODE bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" generatetoaddress $BLOCKS "$ADDR"
  BAL=$(docker exec $NODE bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" getbalance)
  echo "✅ Mined $BLOCKS blocks. Current balance on $NODE: $BAL BTC"
}


# === BALANCE ===
function show_balance() {
  NODE=$1

  BAL=$(docker exec $NODE bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" getbalance)
  echo "💰 Balance for $NODE: $BAL BTC"
}

# === SEND ===
function send_btc() {
  FROM=$1
  TO=$2
  AMOUNT=$3

  echo "📮 Creating new address on $TO..."
  ADDR=$(docker exec $TO bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" getnewaddress)

  echo "💸 Sending $AMOUNT BTC from $FROM to $TO..."
  BAL=$(docker exec $FROM bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" getbalance)
  if (( $(echo "$BAL < $AMOUNT" | bc -l) )); then
    echo "⚠️ Insufficient balance ($BAL < $AMOUNT). Mining extra block..."
    exit 1
  fi

  TXID=$(docker exec $FROM bitcoin-cli $REGTEST_OPTS -rpcwallet="wallet" sendtoaddress "$ADDR" "$AMOUNT")
  echo "🔄 TXID: $TXID"

  echo "⛏️ Mining block to confirm..."
  mine_blocks $FROM 1

  echo "✅ Final Balances:"
  show_balance $FROM
  show_balance $TO
}

# === FULL FLOW ===
function full_flow() {
  init_nodes

  BLOCKS=$(docker exec $NODE1 bitcoin-cli $REGTEST_OPTS getblockcount)
  if [ "$BLOCKS" -lt 101 ]; then
    echo "⛏️ Mining 101 blocks to unlock coinbase rewards on $NODE1..."
    mine_blocks $NODE1 101
  fi

  send_btc $NODE1 $NODE2 10
}

# === COMMAND ROUTER ===
case "$1" in
  init)
    init_nodes
    ;;
  mine)
    if [ -z "$2" ] || [ -z "$3" ]; then
      echo "Usage: ./script mine <node_name> <blocks>"
      exit 1
    fi
    mine_blocks "$2" "$3"
    ;;
  send)
    if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
      echo "Usage: ./script send <from_node> <to_node> <amount>"
      exit 1
    fi
    send_btc "$2" "$3" "$4"
    ;;
  balance)
      if [ -z "$2" ]; then
        echo "Usage: ./script balance <node_name>"
        exit 1
      fi
      show_balance "$2"
      ;;
  full_flow)
    full_flow
    ;;
  help|--help|-h)
    print_help
    ;;
  *)
    echo "❌ Unknown command: $1"
    print_help
    exit 1
    ;;
esac
