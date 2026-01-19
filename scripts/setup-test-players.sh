#!/bin/bash
# Usage: ./setup-test-players.sh [count=5]
# Registers, sets name, and joins game for N players
# Deployer pays all gas fees via fee-payer
set -e

cd "$(dirname "$0")/.."
source .env

COUNT=${1:-5}
CONTRACT=${CONTRACT_ADDRESS}
FEE_PAYER_KEY=${ADMIN_PRIVATE_KEY}

for i in $(seq 1 $COUNT); do
  PROFILE="player$i"
  NAME="TestPlayer$i"

  echo ""
  echo "=== Setting up $PROFILE as $NAME ==="

  # 1. Register in whitelist (fee-payer)
  echo "1. Registering..."
  aptos move run \
    --function-id ${CONTRACT}::whitelist::register \
    --profile $PROFILE \
    --fee-payer-private-key $FEE_PAYER_KEY \
    --assume-yes 2>/dev/null || echo "Already registered"

  # 2. Get player address and invite code
  PLAYER_ADDR=$(aptos account lookup-address --profile $PROFILE 2>/dev/null | jq -r '.Result')

  CODE=$(aptos move view \
    --function-id ${CONTRACT}::whitelist::get_invite_code \
    --args "address:$PLAYER_ADDR" \
    --profile $PROFILE 2>/dev/null | jq -r '.Result[0]')

  echo "2. Got code: $CODE"

  # 3. Set display name (fee-payer)
  echo "3. Setting name..."
  aptos move run \
    --function-id ${CONTRACT}::game::set_display_name \
    --args "string:$CODE" "string:$NAME" \
    --profile $PROFILE \
    --fee-payer-private-key $FEE_PAYER_KEY \
    --assume-yes

  # 4. Join game (fee-payer)
  echo "4. Joining game..."
  aptos move run \
    --function-id ${CONTRACT}::game::join_game \
    --args "string:$CODE" \
    --profile $PROFILE \
    --fee-payer-private-key $FEE_PAYER_KEY \
    --assume-yes

  echo "✅ $PROFILE joined as $NAME"
done

echo ""
echo "=== All $COUNT players joined! ==="
