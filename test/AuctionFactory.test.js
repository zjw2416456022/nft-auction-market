const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Auction System Integration", function () {
  let owner, seller, bidder;
  let nft, factory, weth;
  let nftAuctionImpl;

  before(async function () {
    [owner, seller, bidder] = await ethers.getSigners();

    // 1. 部署 NFT 合约
    const NFT = await ethers.getContractFactory("NFT");
    nft = await NFT.deploy();
    await nft.waitForDeployment();

    // 2. 部署 NftAuction 实现合约（逻辑合约，不初始化）
    const NftAuction = await ethers.getContractFactory("NftAuction");
    nftAuctionImpl = await NftAuction.deploy();
    await nftAuctionImpl.waitForDeployment();

    // 3. 部署 WETH9 mock（用于 ERC20 支付测试）
    const WETH9 = await ethers.getContractFactory("WETH9");
    weth = await WETH9.deploy();
    await weth.waitForDeployment();

    // 4. 部署 AuctionFactory
    const AuctionFactory = await ethers.getContractFactory("AuctionFactory");
    factory = await AuctionFactory.deploy(
      await nftAuctionImpl.getAddress(),
      ethers.ZeroAddress, // ethUsdFeed（测试中可填零地址）
      ethers.ZeroAddress  // erc20UsdFeed
    );
    await factory.waitForDeployment();
  });

  beforeEach(async function () {
    // 每次测试前 mint 一个 NFT 给 seller
    await nft.connect(seller).mint();
    const tokenId = 0; // 假设 mint 的第一个 token ID 是 0

    // 批准工厂转移 NFT
    await nft.connect(seller).approve(await factory.getAddress(), tokenId);

    // 创建拍卖（ETH 拍卖）
    this.auctionAddress = await factory
      .connect(seller)
      .createAuction(
        await nft.getAddress(),
        tokenId,
        ethers.parseEther("1"), // 起拍价 1 ETH
        3600,                   // 1 小时
        true,                   // 接受 ETH
        ethers.ZeroAddress      // paymentToken 忽略
      );

    this.auction = await ethers.getContractAt("NftAuction", this.auctionAddress);
  });

  it("ETH Auction Flow", async function () {
    const startingPrice = ethers.parseEther("1");

    // 出价（必须 >= 起拍价）
    await expect(
      this.auction.connect(bidder).bid({ value: startingPrice })
    ).to.changeEtherBalances([bidder], [-startingPrice]);

    // 等待拍卖结束（Hardhat 可快进时间）
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    // 卖家结算
    const sellerBalanceBefore = await ethers.provider.getBalance(seller.address);
    await this.auction.connect(seller).settle();
    const sellerBalanceAfter = await ethers.provider.getBalance(seller.address);

    // 卖家应收到 1 ETH（减去 gas，但测试中通常忽略）
    expect(sellerBalanceAfter).to.be.greaterThan(sellerBalanceBefore);
  });

  // 可选：添加 ERC20 拍卖测试
  it("ERC20 Auction Flow (WETH)", async function () {
    // Mint 并 approve WETH 给新拍卖
    const tokenId = 1;
    await nft.connect(seller).mint();
    await nft.connect(seller).approve(await factory.getAddress(), tokenId);

    const auctionAddr = await factory
      .connect(seller)
      .createAuction(
        await nft.getAddress(),
        tokenId,
        ethers.parseEther("1"),
        3600,
        false,               // 不接受 ETH
        await weth.getAddress()
      );

    const auction = await ethers.getContractAt("NftAuction", auctionAddr);

    // bidder 获取一些 WETH
    await weth.connect(bidder).deposit({ value: ethers.parseEther("2") });
    await weth.connect(bidder).approve(await auction.getAddress(), ethers.parseEther("1"));

    // 出价
    await auction.connect(bidder).bidErc20(ethers.parseEther("1"));

    // 结算
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);
    await auction.connect(seller).settle();

    // 检查 seller 是否收到 WETH
    expect(await weth.balanceOf(seller.address)).to.equal(ethers.parseEther("1"));
  });
});