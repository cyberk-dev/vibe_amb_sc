#!/bin/bash
set -e

PROFILE=${1:-"lucky-testnet"}
SEED=${2:-"lucky_survivor_v1"}
PRIZE_POOL=${3:-1000000}
OLD_CONTRACT=${4:-""}  # Optional: old contract address to withdraw from
# APT FungibleAsset metadata address on Aptos (0xa)
APT_METADATA="0xa"

echo "========================================="
echo "Deploying Lucky Survivor (Resource Account)"
echo "Profile: $PROFILE"
echo "Seed: $SEED"
echo "Prize Pool: $PRIZE_POOL"
echo "Payment Asset: APT ($APT_METADATA)"
if [ -n "$OLD_CONTRACT" ]; then
  echo "Old Contract: $OLD_CONTRACT (will withdraw funds)"
fi
echo "========================================="

# Get deployer address
DEPLOYER=$(aptos config show-profiles --profile $PROFILE 2>/dev/null | jq -r ".Result[\"$PROFILE\"].account")
if [ -z "$DEPLOYER" ] || [ "$DEPLOYER" == "null" ]; then
  echo "Error: Profile $PROFILE not found. Run: aptos init --profile $PROFILE --network testnet"
  exit 1
fi
echo "Deployer Address: $DEPLOYER"

# =========================================
# STEP 0: Withdraw funds from old contract (if provided)
# =========================================
if [ -n "$OLD_CONTRACT" ]; then
  echo ""
  echo "Step 0: Withdrawing funds from old contract..."

  # Try to withdraw all funds from old vault
  aptos move run \
    --function-id ${OLD_CONTRACT}::vault::withdraw_all \
    --args "address:$APT_METADATA" \
    --profile $PROFILE \
    --assume-yes || echo "Warning: Could not withdraw from old contract (may be empty or already withdrawn)"

  echo "Old contract funds withdrawn to deployer wallet."
fi

# Create resource account and publish package
aptos move create-resource-account-and-publish-package \
  --included-artifacts none \
  --address-name lucky_survivor \
  --seed $SEED \
  --named-addresses deployer=$PROFILE \
  --profile $PROFILE \
  --max-gas 100000 \
  --assume-yes

# Derive resource account address
RESOURCE_ADDRESS=$(aptos account derive-resource-account-address --seed $SEED --address $DEPLOYER | jq .Result | tr -d '"' | awk '{print "0x"$1}')

echo ""
echo "Initializing modules..."

# Initialize all modules via router (vault, whitelist, game)
echo "1/2 Initializing all modules via router..."
aptos move run \
  --function-id ${RESOURCE_ADDRESS}::router::initialize_all \
  --args "u64:$PRIZE_POOL" "address:$APT_METADATA" \
  --profile $PROFILE \
  --assume-yes

# Fund vault with prize pool amount
echo "2/2 Funding vault with $PRIZE_POOL APT..."
aptos move run \
  --function-id ${RESOURCE_ADDRESS}::vault::fund_vault \
  --args "address:$APT_METADATA" "u64:$PRIZE_POOL" \
  --profile $PROFILE \
  --assume-yes

echo ""
echo "========================================="
echo "Deployment successful!"
echo "Deployer: $DEPLOYER"
echo "Resource Account: $RESOURCE_ADDRESS"
echo "Seed: $SEED"
echo "Prize Pool: $PRIZE_POOL"
echo "Payment Asset: $APT_METADATA"
echo "Explorer: https://explorer.aptoslabs.com/account/$RESOURCE_ADDRESS?network=testnet"
echo "========================================="

# Save addresses for reference
cat > addresses.json << EOF
{
  "deployer": "$DEPLOYER",
  "lucky_survivor": "$RESOURCE_ADDRESS",
  "seed": "$SEED",
  "prize_pool": $PRIZE_POOL,
  "payment_asset": "$APT_METADATA"
}
EOF
echo "Addresses saved to addresses.json"
