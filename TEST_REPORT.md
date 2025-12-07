# NFT 拍卖市场 - Sepolia 测试网部署地址

**部署时间**：2025年12月  
**网络**：Sepolia  
**测试全绿通过**：3 passing  
**技术栈**：Solidity 0.8.24 + OpenZeppelin v5 + UUPS + Chainlink

| 合约               | 地址                                                                                   | 交易哈希 |
|--------------------|----------------------------------------------------------------------------------------|----------|
| NFT                | 0x741D49aFa12d577bdF89988a72eB93538e760a4D                                   | 0x1371da7de8503c5b6944aa9f8da00bca9aef202e8f944a29cc7d4b517537ad08 |
| Auction（代理）    | 0x6BEF43F8425754b23cE05c43700641d715a97032             | 0x4d75e5b7b197b86c3a06eecade9eb15b72e569161ff64c44e0b2f9cff16f04c7 |
| Auction（实现）    | 0x8afBE5d2D50B39F62073Dd1582D5ecfB89B3D985                                   | 0x31d50eae1ba2b44c73b0e35ee993faa4cd1e78d1b5e31b4993c08cd408369721 |

**Sepolia 浏览器链接**：
- NFT 合约：https://sepolia.etherscan.io/address/0x741D49aFa12d577bdF89988a72eB93538e760a4D
- 拍卖市场（代理）：https://sepolia.etherscan.io/address/0x6BEF43F8425754b23cE05c43700641d715a97032


# NFT 拍卖市场测试报告

**项目名称**：支持 ETH / USDC 双币种美元竞价的 NFT 拍卖市场  
**测试框架**：Hardhat + Mocha + Chai  
**测试环境**：Hardhat Network（EVM Paris）  
**OpenZeppelin 版本**：v5.0.2  
**测试执行时间**：2025年12月

### 测试结果（全部通过）

```bash
  NFT Auction 本地完整测试
    √ 纯 ETH 出价成功 (597ms)
    √ USDC 出价高于 ETH 获胜 (38ms)
    √ 无人出价 → NFT 自动退回卖家

  3 passing (671ms)