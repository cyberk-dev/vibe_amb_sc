#!/bin/bash
set -e

PROFILE=${1:-"lucky-devnet"}
PRIZE_POOL=${2:-100000000}  # Default 1 APT = 100000000 octas

# Get address from profile (JSON output)
ADDRESS=$(aptos config show-profiles --profile $PROFILE 2>/dev/null | grep '"account"' | sed 's/.*: "\(.*\)".*/0x\1/')

echo "========================================="
echo "Initializing Lucky Survivor Game"
echo "Profile: $PROFILE"
echo "Address: $ADDRESS"
echo "Prize Pool: $PRIZE_POOL octas"
echo "========================================="

# Optional: Reset existing game
echo ""
echo "Step 0: Resetting existing game (if any)..."
aptos move run \
  --function-id "${ADDRESS}::game::reset_game" \
  --profile $PROFILE \
  --max-gas 10000 \
  --assume-yes || echo "No existing game to reset"

# Initialize Vault
echo ""
echo "Step 1: Initializing Vault..."
aptos move run \
  --function-id "${ADDRESS}::vault::initialize" \
  --profile $PROFILE \
  --max-gas 10000 \
  --assume-yes

# Initialize Game
echo ""
echo "Step 2: Initializing Game with prize pool..."
aptos move run \
  --function-id "${ADDRESS}::game::initialize" \
  --args "u64:$PRIZE_POOL" \
  --profile $PROFILE \
  --max-gas 10000 \
  --assume-yes

echo ""
echo "========================================="
echo "✅ Initialization complete!"
echo "Vault and Game are ready."
echo "========================================="