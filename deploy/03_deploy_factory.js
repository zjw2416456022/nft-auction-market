const { ethers } = require("hardhat");

module.exports = async ({ deployments, getNamedAccounts, network }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  let ethUsdFeed, erc20UsdFeed;

  if (network.name === "hardhat") {
    // 本地测试：部署 Mock 预言机
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const ethMock = await MockV3Aggregator.deploy(8, 2000e8); // 8 decimals, $2000
    const erc20Mock = await MockV3Aggregator.deploy(8, 10e8);  // $10
    ethUsdFeed = await ethMock.getAddress();
    erc20UsdFeed = await erc20Mock.getAddress();
  } else {
    // Sepolia 测试网地址（Chainlink 官方）
    ethUsdFeed = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // ETH/USD
    erc20UsdFeed = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // 示例：实际应替换为 WETH/USD 或 LINK/USD
  }

  const nftAuctionImpl = await get("NftAuction");

  await deploy("AuctionFactory", {
    from: deployer,
    args: [nftAuctionImpl.address, ethUsdFeed, erc20UsdFeed],
    log: true,
  });
};

module.exports.tags = ["Factory"];
module.exports.dependencies = ["NftAuctionImpl"];