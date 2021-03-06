#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

#shellcheck source=/dev/null
source env.sh

if [[ -d "$CLUSTER"/ledger ]]; then
  echo "Error: $CLUSTER/ledger/ directory already exists"
  exit 1
fi


solana-genesis --version
solana-ledger-tool --version

./keygen.sh

default_arg() {
  declare name=$1
  declare value=$2

  for arg in "${args[@]}"; do
    if [[ $arg = "$name" ]]; then
      return
    fi
  done

  if [[ -n $value ]]; then
    args+=("$name" "$value")
  else
    args+=("$name")
  fi
}

args=(
  --bootstrap-validator-lamports           500000000000 # 500 SOL for voting
  --bootstrap-validator-stake-lamports  500000000000000 # 500,000 SOL
  --rent-burn-percentage 100                            # Burn it all!
  --fee-burn-percentage 100                             # Burn it all!
  --ledger "$CLUSTER"/ledger
  --operating-mode "${OPERATING_MODE:?}"
)

for zone in "${VALIDATOR_ZONES[@]}"; do
  args+=(
    --bootstrap-validator
      "$CLUSTER"/validator-identity-"$zone".json
      "$CLUSTER"/validator-vote-account-"$zone".json
      "$CLUSTER"/validator-stake-account-"$zone".json
  )
done

if [[ -n $BOOTSTRAP_STAKE_AUTHORIZED_PUBKEY ]]; then
  args+=(--bootstrap-stake-authorized-pubkey "$BOOTSTRAP_STAKE_AUTHORIZED_PUBKEY")
fi

if [[ -n $FAUCET_KEYPAIR ]]; then
  args+=(--faucet-pubkey "$CLUSTER"/faucet.json --faucet-lamports 500000000000000000)
fi

if [[ -n $EXTERNAL_ACCOUNTS_FILE_URL ]]; then
  (
    set -x
    wget "$EXTERNAL_ACCOUNTS_FILE_URL" -O "$CLUSTER"/external-accounts.yml
  )
fi
if [[ -n $EXTERNAL_ACCOUNTS_FILE ]]; then
  args+=(--primordial-accounts-file "$EXTERNAL_ACCOUNTS_FILE")
fi

while [[ -n $1 ]]; do
  if [[ ${1:0:1} = - ]]; then
    if [[ $1 = --creation-time ]]; then
      args+=("$1" "$2")
      shift 2
    else
      echo "Unknown argument: $1"
      exit 1
    fi
  else
    echo "Unknown argument: $1"
    exit 1
  fi
done

if [[ -z $CREATION_TIME ]]; then
  CREATION_TIME=$(date --iso-8601=seconds)
fi

default_arg --creation-time "$CREATION_TIME"

{
  (
    set -x
    solana-genesis "${args[@]}"
  )

  echo ==========================================================================
  for keypair in "$CLUSTER"/validator-identity*.json; do
    echo "--trusted validator $(solana-keygen pubkey "$keypair")"
  done
} | tee "$CLUSTER"/genesis-summary.txt
