# NFT Redeemer Contracts

## NFT Redeemer

The `NFTRedeemer` smart contract provides an interface for users to redeem ERC721 non-fungible tokens (NFTs) in exchange for native cryptocurrency (like ETH).

Key features:

- NFT Redemption: Users can redeem their NFTs and receive a predetermined amount of ETH. The redeemed NFTs are transferred to a specified "burner" address, since ERC721s don't support burning natively, and is useful for NFT collections that do not have a burn function.
- Dual Redemption Rates: The contract supports two different payout amounts: a baseRedemptionAmount and an alternateRedemptionAmount.
- Efficient Pricing: A bitmap is used to efficiently track which specific token IDs are eligible for the alternate redemption amount, saving on gas costs.
- Batch Operations: Users can redeem multiple NFTs in a single transaction. The owner can also update the alternate price status for multiple tokens in a batch.
- Admin Controls: The contract owner has administrative privileges to manage the redemption amounts, set the burner address, pause and unpause redemptions, and withdraw funds from the contract.

## NFT Claim Redeemer

The `NFTClaimRedeemer` contract extends the NFTRedeemer contract to add an alternative redemption mechanism. Additionally redeeming an NFT for ETH, this contract allows the owner to assign a specific ETH amount directly to a user's address. The user can then "claim" this amount.

This extension is useful for scenarios where you want to distribute funds to users who may not hold one of the NFTs (e.g. due to not having claimed in time), or to provide an alternative reward system that is not tied to individual token ownership.

Key features:

- Address-Based Claims: The owner can map a specific amount of ETH to be claimed by any given address using the setClaim and setClaimBatch functions.
- Claim Redemption: A user can call redeemUnclaimed to receive the ETH amount assigned to their address.
- One-Time Claims: Once a user redeems their claim, their claimable balance is reset to zero to prevent them from claiming again.

## Deploy

```bash
forge create contracts/nft-redeemer/NFTClaimRedeemer.sol:NFTClaimRedeemer \
  --ledger --rpc-url $RPC_URL \
  --optimize --optimizer-runs 200 -vvv \
  --verify \
  --broadcast \
  --constructor-args 0xNFT $BASE_AMOUNT $ALT_AMOUNT 0xOWNER 0xBURNER
```

## Test

```bash
forge test -vvv --match-path "contracts/nft-redeemer/tests/*"
```
