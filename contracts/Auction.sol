// contracts/Auction.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title NFT 拍卖市场（支持 ETH 和 USDC 双币种出价）
 * @dev 使用 UUPS 代理模式，支持后续升级
 */
contract Auction is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IERC721 public nftContract;           // NFT 合约地址
    IERC20 public paymentToken;           // 支付用的 ERC20，例如 USDC

    AggregatorV3Interface private ethUsdFeed;       // Chainlink ETH/USD 价格预言机
    AggregatorV3Interface private tokenUsdFeed;     // Chainlink USDC/USD 价格预言机

    address public feeTo;                                 // 手续费接收地址（平台钱包）
    uint256 public constant FEE_PRECISION = 10_000;       // 手续费精度：10000 = 100%，方便计算万分比

    // 每场拍卖的信息
    struct AuctionInfo {
        uint256 tokenId;         // 拍卖的 NFT ID
        address seller;          // 卖家
        uint256 endTime;         // 结束时间戳
        address highestBidder;   // 当前最高出价者
        uint256 highestBidUsd;   // 最高出价（美元等值，18位小数）
        uint256 rawAmount;       // 实际支付的原始数量（wei 或 token 单位）
        bool    isEth;           // true=ETH 出价，false=ERC20 出价
        bool    ended;           // 是否已结束
    }

    mapping(uint256 => AuctionInfo) public auctions; // auctionId => 信息
    uint256 public auctionCount;                     // 拍卖计数器

    event AuctionCreated(uint256 indexed auctionId, uint256 tokenId, address seller, uint256 duration);
    event NewBid(uint256 indexed auctionId, address bidder, uint256 usdAmount, bool isEth);
    event AuctionEnded(uint256 indexed auctionId, address winner, uint256 usdAmount, uint256 feeAmount);
    event AuctionNoBid(uint256 indexed auctionId); // 无人出价的情况
    event FeeWithdrawn(address indexed to, uint256 ethAmount, uint256 tokenAmount); // 平台提取手续费事件

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // 防止直接调用实现合约
    }

    /**
     * @dev 代理初始化函数（只调用一次）
     * @param _nft NFT 合约地址
     * @param _paymentToken ERC20 代币地址（如 USDC）
     * @param _ethUsdFeed Chainlink ETH/USD 预言机地址
     * @param _tokenUsdFeed Chainlink USDC/USD 预言机地址
     * @param _feeTo 平台手续费接收地址（设为 owner 或多签钱包）
     */
    function initialize(
        address _nft,
        address _paymentToken,
        address _ethUsdFeed,
        address _tokenUsdFeed,
        address _feeTo
    ) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        nftContract   = IERC721(_nft);
        paymentToken  = IERC20(_paymentToken);
        ethUsdFeed    = AggregatorV3Interface(_ethUsdFeed);
        tokenUsdFeed  = AggregatorV3Interface(_tokenUsdFeed);
        feeTo         = _feeTo;
    }

    // 只有 owner 可以升级合约
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 根据成交金额（美元等值）计算手续费率
     *      < $1,000      → 2.5%（250/10000）
     *      $1,000~$10,000 → 1.5%（150/10000）
     *      ≥ $10,000     → 0.8%（80/10000）
     */
    function _calculateFeeRate(uint256 usdAmount) internal pure returns (uint256) {
        if (usdAmount < 1_000 * 1e18) {
            return 250;   // 2.5%
        } else if (usdAmount < 10_000 * 1e18) {
            return 150;   // 1.5%
        } else {
            return 80;    // 0.8%
        }
    }

    /**
     * @dev 计算手续费并拆分金额
     * @return netAmount 卖家实际收到
     * @return feeAmount 平台手续费
     */
    function _splitFee(
        uint256 rawAmount,
        uint256 usdAmount
    ) internal pure returns (uint256 netAmount, uint256 feeAmount) {
        uint256 feeRate = _calculateFeeRate(usdAmount);
        feeAmount = (rawAmount * feeRate) / FEE_PRECISION;
        netAmount = rawAmount - feeAmount;
    }


    /**
     * @dev 创建一场拍卖
     * @param tokenId 要拍卖的 NFT ID
     * @param durationSeconds 拍卖持续时间（秒）
     */
    function createAuction(uint256 tokenId, uint256 durationSeconds) external nonReentrant {
        require(durationSeconds >= 300, unicode"最短5分钟"); // 防止恶意短时间拍卖

        // 将 NFT 转入拍卖合约
        nftContract.transferFrom(msg.sender, address(this), tokenId);

        uint256 auctionId = auctionCount++;
        auctions[auctionId] = AuctionInfo({
            tokenId: tokenId,
            seller: msg.sender,
            endTime: block.timestamp + durationSeconds,
            highestBidder: address(0),
            highestBidUsd: 0,
            rawAmount: 0,
            isEth: false,
            ended: false
        });

        emit AuctionCreated(auctionId, tokenId, msg.sender, durationSeconds);
    }

    /**
     * @dev 用 ETH 出价
     */
    function bidWithEth(uint256 auctionId) external payable nonReentrant {
        _processBid(auctionId, true, msg.value);
    }

    /**
     * @dev 用 ERC20（USDC）出价
     */
    function bidWithToken(uint256 auctionId, uint256 amount) external nonReentrant {
        require(paymentToken.transferFrom(msg.sender, address(this), amount), unicode"转账失败");
        _processBid(auctionId, false, amount);
    }

    /**
     * @dev 内部统一出价逻辑（美元比较）
     */
    function _processBid(uint256 auctionId, bool isEth, uint256 rawAmount) internal {
        AuctionInfo storage a = auctions[auctionId];
        require(block.timestamp < a.endTime, unicode"拍卖已结束");
        require(!a.ended, unicode"已结算");

        uint256 usdValue = _toUsdValue(isEth, rawAmount);
        require(usdValue > a.highestBidUsd, unicode"出价必须高于当前最高");

        // 退还上一位出价者的资金（退全款，不扣手续费）
        if (a.highestBidder != address(address(0))) {
            if (a.isEth) {
                (bool success, ) = payable(a.highestBidder).call{value: a.rawAmount}("");
                require(success, unicode"ETH 退还失败");
            } else {
                paymentToken.transfer(a.highestBidder, a.rawAmount);
            }
        }

        // 更新最高出价
        a.highestBidder = msg.sender;
        a.highestBidUsd = usdValue;
        a.rawAmount     = rawAmount;
        a.isEth         = isEth;

        emit NewBid(auctionId, msg.sender, usdValue, isEth);
    }

    /**
     * @dev 结束拍卖（核心逻辑：计算手续费 + 分配资金）
     */
    function endAuction(uint256 auctionId) external nonReentrant {
        AuctionInfo storage a = auctions[auctionId];
        require(block.timestamp >= a.endTime, unicode"未到结束时间");
        require(!a.ended, unicode"已结束");

        a.ended = true;

        if (a.highestBidder == address(0)) {
            // 无人出价，归还 NFT 给卖家
            nftContract.safeTransferFrom(address(this), a.seller, a.tokenId);
            emit AuctionNoBid(auctionId);
        } else {
            // 有出价：计算手续费
            (uint256 netAmount, uint256 feeAmount) = _splitFee(a.rawAmount, a.highestBidUsd);

            // 转移 NFT 给赢家
            nftContract.safeTransferFrom(address(this), a.highestBidder, a.tokenId);

            // 给卖家转净收入，平台收手续费
            if (a.isEth) {
                (bool success1, ) = payable(a.seller).call{value: netAmount}("");
                (bool success2, ) = payable(feeTo).call{value: feeAmount}("");
                require(success1 && success2, unicode"ETH 转账失败");
            } else {
                paymentToken.transfer(a.seller, netAmount);
                paymentToken.transfer(feeTo, feeAmount);
            }

            emit AuctionEnded(auctionId, a.highestBidder, a.highestBidUsd, feeAmount);
        }
    }

    /**
     * @dev 将原始金额转换为美元等值（18位小数）
     */
    function _toUsdValue(bool isEth, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface feed = isEth ? ethUsdFeed : tokenUsdFeed;
        (, int256 price, , , ) = feed.latestRoundData();
        require(price > 0, unicode"预言机价格错误");

        // Chainlink 价格有 8 位小数 → 转成 18 位
        return (amount * uint256(price)) / 1e8;
    }

    function getAuction(uint256 auctionId) external view returns (AuctionInfo memory) {
        return auctions[auctionId];
    }

    /**
     * @dev 平台 owner 提取合约中累积的 ETH 和 USDC 手续费
     */
    function withdrawFees() external onlyOwner {
        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = paymentToken.balanceOf(address(this));

        if (ethBalance > 0) {
            (bool success, ) = payable(owner()).call{value: ethBalance}("");
            require(success, "ETH withdraw failed");
        }

        if (tokenBalance > 0) {
            paymentToken.transfer(owner(), tokenBalance);
        }

        emit FeeWithdrawn(owner(), ethBalance, tokenBalance);
    }
}