// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title NftAuction
 * @dev 单个 NFT 拍卖合约，支持 ETH 或任意 ERC20 出价。
 *      使用 UUPS 模式支持未来升级，每个拍卖实例独立部署（由 Factory 创建）。
 */
contract NftAuction is Initializable, ReentrancyGuardUpgradeable, UUPSUpgradeable, OwnableUpgradeable {
    /// @notice 拍卖核心数据结构
    struct AuctionData {
        address nftContract;     // 被拍卖的 NFT 合约地址
        uint256 tokenId;         // 被拍卖的 NFT ID
        address seller;          // 卖家（也是合约 owner）
        address highestBidder;   // 当前最高出价者
        uint256 highestBid;      // 最高出价金额（单位：wei 或 token 单位）
        bool isEth;              // true = 接受 ETH；false = 接受 ERC20
        address paymentToken;    // 若 isEth=false，记录使用的 ERC20 地址（如 WETH）
        uint256 endTime;         // 拍卖结束时间戳
        bool settled;            // 是否已结算（防止重复结算）
        uint256 startingPrice;   // 起拍价（与出价单位一致）
    }

    // 存储当前拍卖的全部信息（每个合约只管一个拍卖）
    AuctionData public auction;

    // Chainlink ETH/USD 预言机（固定使用）
    AggregatorV3Interface public ethUsdFeed;
    
    // 支持多个 ERC20 的价格预言机映射：tokenAddress => priceFeed
    mapping(address => AggregatorV3Interface) public priceFeeds;

    // 事件：记录出价
    event BidPlaced(address indexed bidder, uint256 amount, bool isEth);
    
    // 事件：记录结算
    event AuctionSettled(address winner, uint256 winningAmount);

    /**
     * @dev 构造函数：禁用初始化器，确保只能通过 initialize 初始化（UUPS 安全要求）
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数（仅可调用一次）
     * @param _seller 卖家地址（将成为合约 owner）
     * @param _nftContract NFT 合约地址
     * @param _tokenId 要拍卖的 NFT ID
     * @param _startingPrice 起拍价（单位与支付方式一致）
     * @param _duration 拍卖持续时间（秒），至少 1 小时
     * @param _isEth 是否接受 ETH
     * @param _paymentToken 若 _isEth=false，传入 ERC20 地址（如 WETH）
     * @param _ethUsdFeed Chainlink ETH/USD 预言机地址
     * @param _erc20UsdFeed Chainlink ERC20/USD 预言机地址（仅用于 _paymentToken）
     */
    function initialize(
        address _seller,
        address _nftContract,
        uint256 _tokenId,
        uint256 _startingPrice,
        uint256 _duration,
        bool _isEth,
        address _paymentToken,
        address _ethUsdFeed,
        address _erc20UsdFeed
    ) public initializer {
        // 初始化 OpenZeppelin 组件
        __Ownable_init(_seller); // 卖家成为 owner，可控制升级和结算
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // 参数校验
        require(_duration >= 1 hours, "Auction duration must be at least 1 hour");
        require(_startingPrice > 0, "Starting price must be greater than 0");

        // 将 NFT 从卖家转移到本合约（锁定）
        IERC721(_nftContract).transferFrom(_seller, address(this), _tokenId);

        // 初始化拍卖数据
        auction = AuctionData({
            nftContract: _nftContract,
            tokenId: _tokenId,
            seller: _seller,
            highestBidder: address(0),
            highestBid: 0,
            isEth: _isEth,
            paymentToken: _isEth ? address(0) : _paymentToken,
            endTime: block.timestamp + _duration,
            settled: false,
            startingPrice: _startingPrice
        });

        // 设置预言机
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        if (!_isEth) {
            // 为该 ERC20 注册价格预言机
            priceFeeds[_paymentToken] = AggregatorV3Interface(_erc20UsdFeed);
        }
    }

    /**
     * @dev 使用 ETH 出价（必须附带 msg.value）
     */
    function placeBid() external payable nonReentrant {
        require(!auction.settled, "Auction already settled");
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(auction.isEth, "This auction only accepts ETH");
        require(msg.value >= auction.startingPrice, "Bid below starting price");
        require(msg.value > auction.highestBid, "Bid must be higher than current highest");

        // 退还上一个出价者
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        // 更新最高出价
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(msg.sender, msg.value, true);
    }

    /**
     * @dev 使用 ERC20 出价（需提前 approve 本合约）
     * @param amount 出价金额（单位：token）
     */
    function placeBidWithERC20(uint256 amount) external nonReentrant {
        require(!auction.settled, "Auction already settled");
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(!auction.isEth, "This auction only accepts ERC20");
        require(amount >= auction.startingPrice, "Bid below starting price");
        require(amount > auction.highestBid, "Bid must be higher than current highest");

        // 从出价者扣款
        IERC20(auction.paymentToken).transferFrom(msg.sender, address(this), amount);

        // 退还上一个出价者
        if (auction.highestBidder != address(0)) {
            IERC20(auction.paymentToken).transfer(auction.highestBidder, auction.highestBid);
        }

        // 更新最高出价
        auction.highestBidder = msg.sender;
        auction.highestBid = amount;

        emit BidPlaced(msg.sender, amount, false);
    }

    /**
     * @dev 结算拍卖：将 NFT 给赢家，资金给卖家
     *      任何人都可调用（激励及时结算）
     */
    function settleAuction() external nonReentrant {
        require(block.timestamp >= auction.endTime, "Auction not ended yet");
        require(!auction.settled, "Already settled");
        require(auction.highestBidder != address(0), "No valid bids");

        auction.settled = true;

        // 转移 NFT 给赢家
        IERC721(auction.nftContract).transferFrom(address(this), auction.highestBidder, auction.tokenId);

        // 转移资金给卖家
        if (auction.isEth) {
            payable(auction.seller).transfer(auction.highestBid);
        } else {
            IERC20(auction.paymentToken).transfer(auction.seller, auction.highestBid);
        }

        emit AuctionSettled(auction.highestBidder, auction.highestBid);
    }

    /**
     * @dev 获取当前最高出价的美元价值（用于前端展示）
     * @return usdValue 单位：1e8（保留 8 位小数）
     */
    function getBidInUsd() external view returns (uint256) {
        if (auction.highestBid == 0) return 0;

        if (auction.isEth) {
            (, int256 price,,,) = ethUsdFeed.latestRoundData();
            return (auction.highestBid * uint256(price)) / 1e8;
        } else {
            AggregatorV3Interface feed = priceFeeds[auction.paymentToken];
            (, int256 price,,,) = feed.latestRoundData();
            return (auction.highestBid * uint256(price)) / 1e8;
        }
    }

    /**
     * @dev UUPS 升级授权：仅 owner（即卖家）可升级
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}