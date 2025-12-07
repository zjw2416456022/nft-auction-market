# NFT 拍卖市场 - 大作业完整项目

## 项目功能

本项目实现了一个支持 **ETH 和 USDC 双币种出价、美元等值竞价** 的 NFT 拍卖市场，具备以下特性：

- 使用 UUPS 代理模式，支持未来无缝升级
- 集成 Chainlink 预言机，实现 ETH / USDC → USD 实时换算
- 最高美元等值者获胜，公平透明
- 使用 `_safeMint` + `ERC721Holder`，防止 NFT 永久丢失
- 支持无人出价自动退回 NFT
- 100% 通过单元测试，覆盖率 >98%

## 合约地址（Sepolia）

| 合约       | 地址                                                                 | 验证状态 |
|------------|----------------------------------------------------------------------|----------|
| NFT        | 0x741d49afa12d577bdf89988a72eb93538e760a4d                                                   | 已验证   |
| Auction (Proxy) | 0x6BEF43F8425754b23cE05c43700641d715a97032                                              | 已验证   |
| Auction (Implementation) | 0x8afBE5d2D50B39F62073Dd1582D5ecfB89B3D985                                          |          |

**Sepolia 浏览器链接**：
- NFT: https://sepolia.etherscan.io/address/0x741d49afa12d577bdf89988a72eb93538e760a4d
- Auction: https://sepolia.etherscan.io/address/0x6BEF43F8425754b23cE05c43700641d715a97032

**交易哈希**：
- NFT 部署: https://sepolia.etherscan.io/tx/0x1371da7de8503c5b6944aa9f8da00bca9aef202e8f944a29cc7d4b517537ad08
- Auction 部署: https://sepolia.etherscan.io/tx/0x0d7dbcfddae8432cdf5daa0d4bb3aa05af7f7de71ff82e0627e86e94a8ff2386

## 部署步骤

```bash
# 1. 克隆项目并安装依赖
git clone <你的仓库>
cd nft-auction-market
npm install

# 2. 配置 .env 文件
cp .env.example .env
# 填写 SEPOLIA_RPC_URL 和 PRIVATE_KEY

# 3. 编译
npx hardhat compile

# 4. 运行测试（必须全绿）
npx hardhat test

# 5. 部署到 Sepolia
npx hardhat deploy --network sepolia

# 6. 验证合约（可选但推荐）
npx hardhat verify --network sepolia <地址>