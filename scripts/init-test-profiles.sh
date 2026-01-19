#!/bin/bash
# Generate 5 test player profiles (no funding needed)
set -e

cd "$(dirname "$0")/.."

for i in 1 2 3 4 5; do
  if ! aptos config show-profiles 2>/dev/null | grep -q "player$i"; then
    echo "Creating profile player$i..."
    aptos init --profile player$i --network testnet --assume-yes
  else
    echo "Profile player$i already exists"
  fi
done

echo "✅ All test profiles ready"
