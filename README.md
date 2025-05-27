This repository contains the contract for voting on the Cetus hack recovery plan. More information is at https://blog.sui.io/cetus-incident-response-onchain-community-vote/

# Instructions for casting a vote as a validator

First, find a gas coin owned by your validator address.

If you don't have it handy, your validator address can be found in the `Account` field on explorers, (for example: https://suivision.xyz/validator/0x4fffd0005522be4bc029724c7f0f6ed7093a6bf3a09b90e62f61dc15181e1a3e).

You can then find the gas coin via an explorer as well, or by running `sui client gas $your_validator_address`

### Now, set up the shell variables used by the command:

```
ADDRESS=<your validator address>
GAS_COIN=<gas coin id>
PKG=0x4eb9c090cd484778411c32894ec7b936793deaab69f114e9b47d07a58e8f5e5d
GOV_OBJ=0x20f7aad455b839a7aec3be11143da7c7b6b481bfea89396424ea1eac02209e7a

# Set VOTE to either "Yes", "No", or "Abstain". The string is case sensitive.
VOTE=
```

### Next, dry run the transaction - observe the output and make sure that:

1. The transaction succeeded
2. The emitted event contains your intended vote.

```
sui client ptb --dry-run --gas-coin "@$GAS_COIN" --gas-budget 10000000000 --move-call "$PKG::governance_voting::vote" "@$GOV_OBJ" @0x5 "'$VOTE'" @0x6
```

### Lastly, create the serialized tx

```
TX_BYTES=$(sui client ptb --serialize-unsigned-transaction --gas-coin "@$GAS_COIN" --gas-budget 10000000000 --move-call "$PKG::governance_voting::vote" "@$GOV_OBJ" @0x5 "'$VOTE'" @0x6)

echo $TX_BYTES
```

The final command will produce a base64 encoded unsigned transaction. You will need to sign it before it can be executed.

### Cast your final vote

🚨 🚨 🚨 Important: **Votes are final. You cannot change your vote once cast** 🚨 🚨 🚨 

You may have your own tools/procedures for signing. If not, the best way is to go to https://multisig-toolkit.mystenlabs.com/offline-signer, connect the appropriate wallet, and sign. You can either broadcast the transaction from the signer using the execute transaction tab (https://multisig-toolkit.mystenlabs.com/execute-transaction), or else copy the signature from the page and send it using the CLI.

You can also sign with the CLI, if you have your private key in your local keystore.

```
sui keytool sign --address "$ADDRESS" --data "$TX_BYTES"

SIGNATURE=<paste sig from keytool output>
```

Finally, execute the signed transaction

```
SIGNATURE="<paste your signature here>"
sui client execute-signed-tx --tx-bytes "$TX_BYTES" --signatures "$SIGNATURE"
```
