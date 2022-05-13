# Bridge

Allow collateralised bridging of assets between chains:

Bridge to chain:

- Transfer tokens on L2 Deversifi to exchange
- Exchange emits a `withdraw` call and gives tokens to the user on the relevant change from this contact

Bridge from chain

- Call `deposit` with your tokens on the relevant chain
- Exchange will credit you on L2 with the tokens by observing the emitted events
