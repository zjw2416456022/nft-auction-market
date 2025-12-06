// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NFT 拍卖市场（支持 ETH 和 ERC20 出价）
 * @dev 功能：
 *      - 创建拍卖（上架 NFT）
 *      - ETH 或 ERC20 出价
 *      - 拍卖结束后自动结算
 *      - 集成 Chainlink 预言机获取 USD 价格
 *      - 支持 UUPS 升级
 */
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AuctionMarket is 
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /// @notice 拍卖信息结构体
    struct Auction {
        address nftContract;    // NFT 合约地址
        uint256 tokenId;        // NFT Token ID
        address seller;         // 卖家地址
        address highestBidder;  // 最高出价者
        uint256 highestBid;     // 最高出价金额
        bool isEth;             // true=ETH, false=ERC20
        uint256 endTime;        // 拍卖结束时间
        bool settled;           // 是否已结算
        uint256 startingPrice;  // 起拍价
    }

    /// @notice 拍卖 ID => 拍卖详情的映射
    mapping(uint256 => Auction) public auctions;
    
    /// @notice 拍卖计数器（自增 ID）
    uint256 public auctionCounter;
    
    /// @notice Chainlink ETH/USD 价格预言机
    AggregatorV3Interface public ethUsdFeed;
    
    /// @notice Chainlink ERC20/USD 价格预言机（例如 LINK/USD）
    AggregatorV3Interface public erc20UsdFeed;
    
    /// @notice ERC20 代币地址（例如 WETH）
    address public wethToken;

    // ===== 事件定义 =====
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 startingPrice,
        uint256 endTime
    );
    
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount,
        bool isEth
    );
    
    event AuctionSettled(
        uint256 indexed auctionId,
        address winner,
        uint256 winningAmount
    );

    /**
     * @dev 构造函数（仅设置不可变变量 wethToken）
     *      其他状态变量在 initialize() 中初始化
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _wethToken) {
        wethToken = _wethToken;
        _disableInitializers();
    }

    /**
     * @dev 初始化合约（UUPS 代理必需）
     * @param initialOwner 初始所有者
     * @param _ethUsdFeed Chainlink ETH/USD 预言机地址
     * @param _erc20UsdFeed Chainlink ERC20/USD 预言机地址
     */
    function initialize(
        address initialOwner,
        address _ethUsdFeed,
        address _erc20UsdFeed
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        erc20UsdFeed = AggregatorV3Interface(_erc20UsdFeed);
        auctionCounter = 0;
    }

    /**
     * @dev 创建新拍卖
     * @param nftContract NFT 合约地址
     * @param tokenId 要拍卖的 Token ID
     * @param startingPrice 起拍价
     * @param duration 拍卖持续时间（秒）
     * @param isEth true=接受 ETH, false=接受 ERC20
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration,
        bool isEth
    ) external nonReentrant {
        // 验证调用者是 NFT 拥有者
        require(IERC721Upgradeable(nftContract).ownerOf(tokenId) == msg.sender, "不是 NFT 拥有者");
        require(duration >= 1 hours, "拍卖时间至少 1 小时");
        require(startingPrice > 0, "起拍价必须大于 0");

        // 将 NFT 转移到拍卖合约
        IERC721Upgradeable(nftContract).transferFrom(msg.sender, address(this), tokenId);

        // 创建拍卖记录
        auctions[auctionCounter] = Auction({
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            highestBidder: address(0),
            highestBid: 0,
            isEth: isEth,
            endTime: block.timestamp + duration,
            settled: false,
            startingPrice: startingPrice
        });

        emit AuctionCreated(auctionCounter, nftContract, tokenId, msg.sender, startingPrice, block.timestamp + duration);
        auctionCounter++;
    }

    /**
     * @dev 使用 ETH 出价
     * @param auctionId 拍卖 ID
     */
    function placeBid(uint256 auctionId) external payable nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp < auction.endTime, "拍卖已结束");
        require(!auction.settled, "拍卖已结算");
        require(auction.isEth, "此拍卖只接受 ETH");
        require(msg.value > auction.highestBid, "出价必须高于当前最高价");
        require(msg.value >= auction.startingPrice, "出价不能低于起拍价");

        // 退还上一个出价者的资金
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(auctionId, msg.sender, msg.value, true);
    }

    /**
     * @dev 使用 ERC20 出价
     * @param auctionId 拍卖 ID
     * @param amount 出价金额
     */
    function placeBidWithERC20(uint256 auctionId, uint256 amount) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp < auction.endTime, "拍卖已结束");
        require(!auction.settled, "拍卖已结算");
        require(!auction.isEth, "此拍卖只接受 ERC20");
        require(amount > auction.highestBid, "出价必须高于当前最高价");
        require(amount >= auction.startingPrice, "出价不能低于起拍价");

        // 从出价者转移 ERC20
        IERC20Upgradeable(wethToken).transferFrom(msg.sender, address(this), amount);

        // 退还上一个出价者的资金
        if (auction.highestBidder != address(0)) {
            IERC20Upgradeable(wethToken).transfer(auction.highestBidder, auction.highestBid);
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = amount;

        emit BidPlaced(auctionId, msg.sender, amount, false);
    }

    /**
     * @dev 结算拍卖（任何人都可调用）
     * @param auctionId 拍卖 ID
     */
    function settleAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.endTime, "拍卖尚未结束");
        require(!auction.settled, "拍卖已结算");
        require(auction.highestBidder != address(0), "无人出价");

        auction.settled = true;

        // 将 NFT 转移给赢家
        IERC721Upgradeable(auction.nftContract).transferFrom(
            address(this),
            auction.highestBidder,
            auction.tokenId
        );

        // 将资金转移给卖家
        if (auction.isEth) {
            payable(auction.seller).transfer(auction.highestBid);
        } else {
            IERC20Upgradeable(wethToken).transfer(auction.seller, auction.highestBid);
        }

        emit AuctionSettled(auctionId, auction.highestBidder, auction.highestBid);
    }

    /**
     * @dev 获取当前 ETH/USD 价格（Chainlink 数据）
     * @return price 价格（带 8 位小数）
     */
    function getEthToUsdPrice() public view returns (uint256) {
        (, int256 price,,,) = ethUsdFeed.latestRoundData();
        return uint256(price);
    }

    /**
     * @dev 获取当前 ERC20/USD 价格（Chainlink 数据）
     * @return price 价格（带 8 位小数）
     */
    function getErc20ToUsdPrice() public view returns (uint256) {
        (, int256 price,,,) = erc20UsdFeed.latestRoundData();
        return uint256(price);
    }

    /**
     * @dev 将当前最高出价转换为美元价值（用于前端展示）
     * @param auctionId 拍卖 ID
     * @return usdValue 美元价值（单位：wei，需除以 1e8 显示）
     */
    function getBidInUsd(uint256 auctionId) external view returns (uint256) {
        Auction memory auction = auctions[auctionId];
        if (auction.isEth) {
            uint256 ethPrice = getEthToUsdPrice();
            return (auction.highestBid * ethPrice) / 1e8; // ETH/USD feed 有 8 位小数
        } else {
            uint256 erc20Price = getErc20ToUsdPrice();
            return (auction.highestBid * erc20Price) / 1e8; // ERC20/USD feed 有 8 位小数
        }
    }

    /**
     * @dev UUPS 升级权限控制（仅所有者可升级）
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}