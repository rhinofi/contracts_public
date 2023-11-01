# This documentation is intended for audit purposes only and is not intended for regular use. rhino.fi bears no liability for funds lost by using the methods described in this repository and will not refund any funds lost.  All interactions with rhino.fi must occur through the UI and contract interactions are strictly unsupported

<img src="https://avatars1.githubusercontent.com/u/56512535?s=200&v=4" align="right" />

# Bridge

Allow collateralised bridging of assets between chains:

Bridge to chain:

- Transfer tokens on L2 Deversifi to exchange
- Exchange emits a `withdraw` call and gives tokens to the user on the relevant change from this contact

Bridge from chain

- Call `deposit` with your tokens on the relevant chain
- Exchange will credit you on L2 with the tokens by observing the emitted events
