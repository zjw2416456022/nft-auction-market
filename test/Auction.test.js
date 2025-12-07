// test/Auction.test.js
const { expect } = require("chai");
const { ethers, upgrades, network } = require("hardhat");

async function deployAll() {
  const [owner, seller, bidder1, bidder2] = await ethers.getSigners();

  // 1. 部署 NFT
  const NFT = await ethers.getContractFactory("NFT");
  const nft = await NFT.deploy();
  await nft.waitForDeployment();

  // 2. 部署 Mock USDC
  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const usdc = await MockUSDC.deploy();
  await usdc.waitForDeployment();

  // 3. 部署 Mock Chainlink 价格预言机
  const MockV3 = await ethers.getContractFactory("MockV3Aggregator");
  const ethFeed = await MockV3.deploy(8, 2000e8);   // 1 ETH = $2000
  const usdcFeed = await MockV3.deploy(8, 1e8);     // 1 USDC = $1

  // 4. 部署 Auction 代理
  const Auction = await ethers.getContractFactory("Auction");
  const auction = await upgrades.deployProxy(Auction, [
    await nft.getAddress(),
    await usdc.getAddress(),
    await ethFeed.getAddress(),
    await usdcFeed.getAddress(),
  ], { kind: "uups" });
  await auction.waitForDeployment();

  // 给卖家铸一个 NFT
  await nft.connect(owner).mint(seller.address);

  return { nft, auction, usdc, owner, seller, bidder1, bidder2 };
}

describe("NFT Auction 本地完整测试", function () {
  it("纯 ETH 出价成功", async function () {
    // 每次测试都重新部署一套新环境，避免状态污染
    const { nft, auction, seller, bidder1 } = await deployAll();
    // 卖家授权 Auction 合约操作自己的 NFT（tokenId = 0）
    await nft.connect(seller).approve(auction.target, 0);
    // 卖家创建一场 600 秒（10 分钟）的拍卖
    await auction.connect(seller).createAuction(0, 600);
    // bidder1 用 1 ETH 出价
    await auction.connect(bidder1).bidWithEth(0, { value: ethers.parseEther("1") });
    // 时间快进 601 秒，让拍卖过期
    await network.provider.send("evm_increaseTime", [601]);
    // 结束拍卖
    await auction.endAuction(0);
    // 断言：NFT 应该属于 bidder1
    expect(await nft.ownerOf(0)).to.equal(bidder1.address);
  });

  it("USDC 出价高于 ETH 获胜", async function () {
    const { nft, auction, usdc, seller, bidder1, bidder2 } = await deployAll(); // 正确！不重复

    await nft.connect(seller).approve(auction.target, 0);
    await auction.connect(seller).createAuction(0, 600);

    // ETH 出价 $2000
    await auction.connect(bidder1).bidWithEth(0, { value: ethers.parseEther("1") });

    // 给 bidder2 发 3000 USDC
    await usdc.mint(bidder2.address, ethers.parseUnits("3000", 18));
    // bidder2 授权 Auction 合约花费他的 USDC
    await usdc.connect(bidder2).approve(auction.target, ethers.parseUnits("3000", 18));
    // bidder2 用 USDC 出价 $2500 更高
    await auction.connect(bidder2).bidWithToken(0, ethers.parseUnits("2500", 18));

    await network.provider.send("evm_increaseTime", [601]);
    await auction.endAuction(0);

    // 断言：NFT 应该属于 bidder2
    expect(await nft.ownerOf(0)).to.equal(bidder2.address);
  });

  it("无人出价 → NFT 自动退回卖家", async function () {
    const { nft, auction, seller } = await deployAll();

    await nft.connect(seller).approve(auction.target, 0);
    await auction.connect(seller).createAuction(0, 300);// 5 分钟拍卖

    // 时间快进，让拍卖过期
    await network.provider.send("evm_increaseTime", [301]);
    // 结束拍卖
    await auction.endAuction(0);
    // 断言：NFT 还在卖家手里
    expect(await nft.ownerOf(0)).to.equal(seller.address);
  });
});