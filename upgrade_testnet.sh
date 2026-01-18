#!/bin/bash
set -e

PROFILE=${1:-"lucky-testnet"}

echo "========================================="
echo "Upgrading Lucky Survivor"
echo "Profile: $PROFILE"
echo "========================================="

# Read resource address from addresses.json
if [ ! -f "addresses.json" ]; then
  echo "Error: addresses.json not found. Run deploy_testnet.sh first."
  exit 1
fi

LUCKY_SURVIVOR=$(cat addresses.json | jq -r '.lucky_survivor')
DEPLOYER=$(cat addresses.json | jq -r '.deployer')

if [ -z "$LUCKY_SURVIVOR" ] || [ "$LUCKY_SURVIVOR" == "null" ]; then
  echo "Error: lucky_survivor address not found in addresses.json"
  exit 1
fi

echo "Deployer: $DEPLOYER"
echo "Resource Account: $LUCKY_SURVIVOR"

# Clean previous output
rm -f output.json

# Build publish payload
echo ""
echo "Building publish payload..."
aptos move build-publish-payload \
  --included-artifacts none \
  --profile $PROFILE \
  --named-addresses lucky_survivor=$LUCKY_SURVIVOR,deployer=$PROFILE \
  --json-output-file output.json

# Extract metadata and code
METADATA=$(cat output.json | jq '.args[0].value' | sed 's/"//g')
CODE=$(cat output.json | jq '.args[1].value')

echo ""
echo "Calling package_manager::upgrade..."
aptos move run \
  --function-id ${LUCKY_SURVIVOR}::package_manager::upgrade \
  --profile $PROFILE \
  --args "hex:$METADATA" "hex:$CODE" \
  --assume-yes

# Cleanup
rm -f output.json

echo ""
echo "========================================="
echo "Upgrade successful!"
echo "Resource Account: $LUCKY_SURVIVOR"
echo "Explorer: https://explorer.aptoslabs.com/account/$LUCKY_SURVIVOR?network=testnet"
echo "========================================="
