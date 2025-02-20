#!/bin/sh

set -e

echo "##### Upgrade module #####"

# Profile is the account you used to execute transaction
# Run "aptos init" to create the profile, then get the profile name from .aptos/config.yaml
PUBLISHER_PROFILE=marketplace

CONTRACT_ADDRESS=$(cat contract_address_marketplace.txt)

aptos move upgrade-object-package \
  --object-address $CONTRACT_ADDRESS \
  --named-addresses marketplace_addr=$CONTRACT_ADDRESS \
  --profile $PUBLISHER_PROFILE \
  --assume-yes
