#!/bin/bash
# Usage: ./players-choose-bao.sh [count=5] [target=self]
# target: "self" = each player keeps their bao, or an address to give to
set -e

cd "$(dirname "$0")/.."
source .env

COUNT=${1:-5}
TARGET_MODE=${2:-self}
CONTRACT=${CONTRACT_ADDRESS}
FEE_PAYER_KEY=${ADMIN_PRIVATE_KEY}

for i in $(seq 1 $COUNT); do
  PROFILE="player$i"

  if [ "$TARGET_MODE" == "self" ]; then
    TARGET=$(aptos account lookup-address --profile $PROFILE 2>/dev/null | jq -r '.Result')
  else
    TARGET=$TARGET_MODE
  fi

  echo "=== $PROFILE choosing bao → ${TARGET_MODE} ==="

  aptos move run \
    --function-id ${CONTRACT}::game::choose_bao \
    --args "address:$TARGET" \
    --profile $PROFILE \
    --fee-payer-private-key $FEE_PAYER_KEY \
    --assume-yes

  echo "✅ $PROFILE chose bao"
done

echo ""
echo "=== All $COUNT players chose bao ==="
