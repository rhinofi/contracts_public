# Rhino.fi TON Bridge Contract

## Overview
The following contract is intended to be used as a bridge between the Rhino.fi exchange and the TON blockchain. It allows for the transfer of tokens between the two chains.

## External libraries

### FunC Standard Library
This contract uses the following version of stdlib.fc:

https://github.com/ton-blockchain/ton/blob/func-0.4.4/crypto/smartcont/stdlib.fc

#### Jetton imports
This contract uses the jetton version v1.07 under folder jetton for necessary jetton imports: 

https://github.com/ton-blockchain/token-contract/blob/jetton-v1.07/

### Files

1) jetton/* : Copy of the jetton contracts (used only for mock testing). Out of the scope of the audit.
2) imports/stdlib.fc : Copy of the stdlib.fc file used in the jetton contracts. To consider for the audit if there are any related security issues.
3) imports: dependencies for the bridge contract. Should be audited, as they contain code written by Rhino.fi
4) bridge_contract.fc : The bridge contract, should be audited.

### Running the tests

1) Install the dependencies with `npm install`
2) Run the tests with `npm run test`


## Operating conditions

The contract must have a minimum balance of 5 TON to ensure there is enough TON to pay for storage.

## Contract functions

### op::transfer_notification()

Handles the Jetton transfer notification from bridge jetton wallet. In order for the deposit to be valid the jetton transfer must include:
 1) the EVM address in the forward_payload
 2) Enough TON to cover the gas fees needed to process the transfer_notification

Only messages coming from whitelisted jetton wallets are accepted. If the sender of the trasfer_notification is not in the whitelist, the Jettons will be rejected and the contract will initiate a Jetton transfer to send the Jettons back to the user.

If the Jetton wallet address is whitelisted, the contract will load the deposit limit from a dictionary. If the deposit exceeds the configured limit amount, the contract will initiate a Jetton transfer to send the Jettons back to the user, otherwise the Jettons will be accepted and an event will be emitted. The backend will process the event and credit the Jettons to the user.

### op::deposit_native

Handles the Jetton deposit native. This feature is disabled by default, in order to enable it, the bridge address must be whitelisted as a Jetton wallet. This is used as special address to store the deposit limits for the native token. 

Requires to add the following information in the message:
1) The EVM address where the backend will credit deposit
2) How much TON to deposit: excess TON attached will be used for deposit gas. 

### op::withdraw_jetton

Only authorized users can call this function. Intended to be used by the backend to withdraw Jettons from the bridge contract to the user's wallet. 

### op::withdraw_native

Only authorized users can call this function. Intended to be used by the backend to withdraw TON from the bridge contract to the user's wallet. 

### op::set_deposit_limit

Only authorized users can call this function. Sets the deposit limit for a Jetton wallet, using the contract address as a Jetton wallet address sets the deposit limit for TON. 

### op::block_global_deposits

Only authorized users can call this function. Blocks or allows Jetton and native deposits. It overrides the deposit limit logic.

### op::authorize

Only the owner of the contract can call this function. Adds a new address into the authorization list.

### op::upgrade_with_data

Only the owner of the contract can call this function. Upgrades the contract to a new version and (if present) overwrites the contract data with the provided data.
Data is meant to be provided only when the storage layout if modified and it's no longer compatible with the new storage layout.

### op::transfer_ownership

Only the owner of the contract can call this function. Sets the pending owner to the provided address, the new owner must accept the ownership via accept_ownership function. The current owner continues to own the contract until the new owner accepts the ownership.

### op::accept_ownership

The new owner can call this function to accept the ownership of the contract.
