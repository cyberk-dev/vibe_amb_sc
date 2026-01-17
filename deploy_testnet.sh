#!/bin/bash
set -e

PROFILE=${1:-"lucky-testnet"}
NETWORK="testnet"

echo "========================================="
echo "Deploying Lucky Survivor to $NETWORK"
echo "Profile: $PROFILE"
echo "========================================="

if ! aptos config show-profiles | grep -q "$PROFILE"; then
  echo "Profile $PROFILE not found. Creating..."
  aptos init --profile $PROFILE --network $NETWORK
  aptos account fund-with-faucet --profile $PROFILE --amount 100000000
fi

ADDRESS=$(aptos config show-profiles --profile $PROFILE 2>/dev/null | grep "account:" | awk '{print $2}')
echo "Deployer Address: $ADDRESS"

echo ""
echo "Publishing package..."
aptos move publish \
  --package-dir . \
  --named-addresses lucky_survivor=$PROFILE \
  --profile $PROFILE \
  --max-gas 100000 \
  --assume-yes
echo ""
echo "========================================="
echo "✅ Deployment successful!"
echo "Contract Address: $ADDRESS"
echo "Explorer: [https://explorer.aptoslabs.com/account/$ADDRESS?network=$NETWORK](https://explorer.aptoslabs.com/account/$ADDRESS?network=$NETWORK)"
echo "========================================="