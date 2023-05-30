# rhino.fi's Public contracts

Pure solidity repository of rhino.fi's contracts. No dependencies are included and may be required for compilation of the contracts (openzepplin's contracts)

## Latest Deployed Versions

#### Ethereum Mainnet
- Deposit proxy - [0xeD9d63a96c27f87B07115b56b2e3572827f21646](https://etherscan.io/address/0xeD9d63a96c27f87B07115b56b2e3572827f21646)
- StarkEx Bridge - [0x5d22045daceab03b158031ecb7d9d06fad24609b](https://etherscan.io/address/0x5d22045daceab03b158031ecb7d9d06fad24609b)
- Fast Withdrawal Transfer Proxy - [0xc3ca38091061e3e5358a52d74730f16c60ca9c26](https://etherscan.io/address/0xc3ca38091061e3e5358a52d74730f16c60ca9c26)
- DA Committee - [0x28780349a33eee56bb92241baab8095449e24306](https://etherscan.io/address/0x28780349a33eee56bb92241baab8095449e24306)
- DVF Token - [0xdddddd4301a082e62e84e43f474f044423921918](https://etherscan.io/token/0xdddddd4301a082e62e84e43f474f044423921918)
- xDVF Token - [0xdddd0e38d30dd29c683033fa0132f868597763ab](https://etherscan.io/token/0xdddd0e38d30dd29c683033fa0132f868597763ab)
- DAO - [0x4788Aa3bECBf5f7c9Fd058372b4a3FC7C75DF201](https://etherscan.io/address/0x4788Aa3bECBf5f7c9Fd058372b4a3FC7C75DF201)
- DAO Vested Treasury - [0x65d57b1e6570f5c636b8dd64c186ac304a4c0ce9](https://etherscan.io/address/0x65d57b1e6570f5c636b8dd64c186ac304a4c0ce9)
- AMM factory - [0x1264f802364E0776b9A9e3d161B43c7333aC08b2](https://etherscan.io/address/0x1264f802364E0776b9A9e3d161B43c7333aC08b2)
- AMM router - [0xDD1891fea0446f56726d4c4eDFc11cA13F943CA2](https://etherscan.io/address/0xDD1891fea0446f56726d4c4eDFc11cA13F943CA2)
- AMM LP Proxy beacon - [0x0bCa65bf4b4c8803d2f0B49353ed57CAAF3d66Dc](https://etherscan.io/address/0x0bCa65bf4b4c8803d2f0B49353ed57CAAF3d66Dc)
- AMM LP implmementation - [0x329F5a8d24503fC00B31b229835b6452A6723ae4](https://etherscan.io/address/0x329F5a8d24503fC00B31b229835b6452A6723ae4)

#### Arbitrum
- Bridge - [0x10417734001162ea139e8b044dfe28dbb8b28ad0](https://arbiscan.io/address/0x10417734001162ea139e8b044dfe28dbb8b28ad0)
- Cross-Swap wallet - [0xCA8E436347a46502E353Cc36b58FE3bB9214D7Fd](https://arbiscan.io/address/0xca8e436347a46502e353cc36b58fe3bb9214d7fd)
- MultiSig - [0x15ca1fC728Cce7cd06151C8007e89dEe70260228](https://arbiscan.io/address/0x15ca1fC728Cce7cd06151C8007e89dEe70260228)
- Timelock - [0xDb5dF800519fa443589Db1458a2A05056D7C9391](https://arbiscan.io/address/0xDb5dF800519fa443589Db1458a2A05056D7C9391)

#### BSC
- Bridge - [0xB80A582fa430645A043bB4f6135321ee01005fEf](https://bscscan.com/address/0xB80A582fa430645A043bB4f6135321ee01005fEf)
- Cross-Swap wallet - [0xca8e436347a46502e353cc36b58fe3bb9214d7fd](https://bscscan.com/address/0xca8e436347a46502e353cc36b58fe3bb9214d7fd)
- MultiSig - [0x7Af3828c0B061552AF3479806Add982eEf04f0c8](https://bscscan.com/address/0x7Af3828c0B061552AF3479806Add982eEf04f0c8)
- Timelock - [0xa3416E2d42D1F15322C1dCD8558302221Aa3A64b](https://bscscan.com/address/0xa3416E2d42D1F15322C1dCD8558302221Aa3A64b)

#### Polygon
- Bridge - [0xba4eee20f434bc3908a0b18da496348657133a7e](https://polygonscan.com/address/0xba4eee20f434bc3908a0b18da496348657133a7e)
- Cross-Swap wallet - [0xda7EeB4049dA84596937127855B50271ad1687E7](https://polygonscan.com/address/0xda7eeb4049da84596937127855b50271ad1687e7)
- MultiSig - [0x249aAbb1d67A76404Cc1197fa37ADAf358B1E212](https://polygonscan.com/address/0x249aAbb1d67A76404Cc1197fa37ADAf358B1E212)
- Timelock - [0x6aF2fD733aCF215684700a616395D2825df83f402](https://polygonscan.com/address/0x6aF2fD733aCF215684700a616395D2825df83f402)

#### zkSync
- Bridge [0x1fa66e2B38d0cC496ec51F81c3e05E6A6708986F](https://explorer.zksync.io/address/0x1fa66e2B38d0cC496ec51F81c3e05E6A6708986F)
- Cross-Swap wallet - N/A
- MultiSig - N/A
- Timelock - N/A

#### zkEVM
- Bridge [0x65A4b8A0927c7FD899aed24356BF83810f7b9A3f](https://zkevm.polygonscan.com/address/0x65A4b8A0927c7FD899aed24356BF83810f7b9A3f)
- Cross-Swap wallet - N/A
- MultiSig - N/A
- Timelock - N/A

## Cross-Swap Wallet

rhino.fi deploys this self-custodial smart-wallet on several chains, and it holds tokens on behalf of users. rhino.fi can broadcast meta-transactions signed by users in order to swap via aggregators such as Paraswap or invest into yield opportunities such as via Beefy Finance.

## Bridge

Bridge funds from rhino.fi's L2 to other chains using collateral. Behaves similar to our FastWithdrawal pool and is not trustless at point of transfer

## AMM

An extension of [UniswapV2](https://github.com/Uniswap/v2-core) smart contracts to allow operations in L2 mode

All core AMM calculations are courtesy of [Uniswap](https://uniswap.org/)
