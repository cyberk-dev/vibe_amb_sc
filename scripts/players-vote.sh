#!/bin/bash
# Usage: ./players-vote.sh [count=5] [choice=1]
# choice: 0=STOP, 1=CONTINUE
set -e

cd "$(dirname "$0")/.."
source .env

COUNT=${1:-5}
CHOICE=${2:-1}
CONTRACT=${CONTRACT_ADDRESS}
FEE_PAYER_KEY=${ADMIN_PRIVATE_KEY}

CHOICE_NAME="CONTINUE"
[ "$CHOICE" == "0" ] && CHOICE_NAME="STOP"

for i in $(seq 1 $COUNT); do
  PROFILE="player$i"

  echo "=== $PROFILE voting $CHOICE_NAME ==="

  aptos move run \
    --function-id ${CONTRACT}::game::vote \
    --args "u8:$CHOICE" \
    --profile $PROFILE \
    --fee-payer-private-key $FEE_PAYER_KEY \
    --assume-yes

  echo "✅ $PROFILE voted $CHOICE_NAME"
done

echo ""
echo "=== All $COUNT players voted $CHOICE_NAME ==="
