# NFT 拍卖市场

## 项目概述

本项目实现了一个支持 **ETH 和 USDC 双币种出价、美元等值竞价** 的 NFT 拍卖市场。主要功能包括：

- 使用 UUPS 代理模式，支持未来无缝升级
- 集成 Chainlink 预言机，实现出价金额实时换算成美元比较
- 支持动态手续费（根据成交金额不同费率）
- 无人出价时 NFT 自动退回卖家
- 所有关键操作都有事件记录，便于前端监听

项目已在 **Sepolia 测试网**成功部署并通过完整功能测试。

## 功能说明

- **NFT 铸造**：通过 `safeMint` 安全铸造，防止 NFT 永久丢失
- **创建拍卖**：卖家上架 NFT，最短持续时间 5 分钟
- **双币种出价**：
  - `bidWithEth()`：用 ETH 出价
  - `bidWithToken()`：用 USDC 出价
- **美元等值比较**：通过 Chainlink 获取实时价格，统一按美元价值比较
- **动态手续费**：
  - < $1,000 → 2.5%
  - $1,000 ~ $10,000 → 1.5%
  - ≥ $10,000 → 0.8%
  - 手续费直接转给平台地址（`feeTo`）
- **拍卖结束**：自动转移 NFT 和资金，包含手续费扣除
- **安全设计**：
  - 使用 `ReentrancyGuard` 防止重入攻击
  - 使用 `safeTransferFrom` 和 `_safeMint`
  - 所有关键操作都有事件触发

## 合约地址（Sepolia 测试网）

| 合约           | 地址                                                                 |
|----------------|----------------------------------------------------------------------|
| NFT            | [0x741D49aFa12d577bdF89988a72eB93538e760a4D](https://sepolia.etherscan.io/address/0x741d49afa12d577bdf89988a72eb93538e760a4d) |
| Auction（代理）| [0x6BEF43F8425754b23cE05c43700641d715a97032](https://sepolia.etherscan.io/address/0x6BEF43F8425754b23cE05c43700641d715a97032) |

> 前端请使用 **Auction 代理地址** `0x6BEF...` 进行交互

## 项目结构

```
contracts/
├── NFT.sol              # 简单的 ERC721 NFT
├── Auction.sol          # 主拍卖合约（支持升级 + 动态手续费）
└── mocks/               # 测试用模拟合约

deploy/
├── 01_deploy_nft.js
└── 02_deploy_auction.js

test/
└── Auction.test.js      # 完整功能测试

hardhat.config.js
.env.example
```

## 技术栈

- Solidity ^0.8.24
- Hardhat + hardhat-deploy + hardhat-upgrades
- OpenZeppelin Contracts v5
- Chainlink 预言机（Sepolia）
- 测试框架：Mocha + Chai

## 测试情况

```bash
 NFT拍卖合约
    手续费结构测试
      ✔ ETH出价$800 → 应用2.5%手续费
      ✔ USDC出价$8000 → 应用1.5%手续费
      ✔ ETH出价$15000 → 应用0.8%手续费
      ✔ 小额出价动态手续费 (<$1000)
      ✔ 高额出价动态手续费 (≥$10000)
      ✔ 平台直接收到手续费（无需提取）
    竞价机制测试
      ✔ 多人激烈竞价 - 最后出价最高者获胜 + 退款
      ✔ ETH + USDC 混合竞价 - 美元最高者获胜
    边界情况测试
      ✔ 无人出价 → NFT 自动退回卖家，无手续费
      ✔ 对不存在的拍卖出价应该失败


  10 passing (1s)
```

## 部署步骤

```bash
# 安装依赖
npm install

# 配置环境变量
cp .env.example .env
# 填写 SEPOLIA_RPC_URL 和 PRIVATE_KEY

# 编译
npx hardhat compile

# 测试（确保全通过）
npx hardhat test

# 部署到 Sepolia
npx hardhat deploy --network sepolia
```

