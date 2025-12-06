// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./NftAuction.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title AuctionFactory
 * @dev Factory contract to deploy individual NftAuction instances via CREATE2.
 *      Each NFT (identified by tokenId) can have at most one auction.
 *      Uses EIP-1167 minimal proxies to reduce deployment cost.
 */
contract AuctionFactory {
    /// @notice Address of the NftAuction implementation contract (immutable).
    address public immutable nftAuctionImplementation;
    
    /// @notice Owner of this factory (can perform admin operations).
    address public owner;
    
    /// @notice Chainlink ETH/USD price feed address (shared by all auctions).
    address public ethUsdFeed;
    
    /// @notice Chainlink ERC20/USD price feed address (shared by all auctions).
    address public erc20UsdFeed;

    /// @notice Maps NFT token ID to its auction proxy address.
    mapping(uint256 => address) public auctionOfToken;
    
    /// @notice List of all deployed auction addresses (for enumeration).
    address[] public allAuctions;

    /// @notice Emitted when a new auction is created.
    /// @param auction The address of the newly created auction proxy.
    /// @param tokenId The NFT token ID being auctioned.
    event AuctionCreated(address indexed auction, uint256 indexed tokenId);

    /// @dev Restricts function access to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "AuctionFactory: caller is not the owner");
        _;
    }

    /**
     * @dev Initializes the factory with implementation and oracle addresses.
     * @param _nftAuctionImpl Address of the NftAuction implementation contract.
     * @param _ethUsdFeed Chainlink ETH/USD price feed.
     * @param _erc20UsdFeed Chainlink ERC20/USD price feed.
     */
    constructor(
        address _nftAuctionImpl,
        address _ethUsdFeed,
        address _erc20UsdFeed
    ) {
        nftAuctionImplementation = _nftAuctionImpl;
        ethUsdFeed = _ethUsdFeed;
        erc20UsdFeed = _erc20UsdFeed;
        owner = msg.sender;
    }

    /**
     * @notice Creates a new auction for a specific NFT.
     * @dev Reverts if caller is not the NFT owner or if an auction already exists.
     * @param nftContract Address of the ERC721 NFT contract.
     * @param tokenId ID of the NFT to be auctioned.
     * @param startingPrice Minimum bid amount (in wei or token units).
     * @param duration Auction duration in seconds.
     * @param isEth If true, accepts ETH; if false, accepts ERC20.
     * @param paymentToken ERC20 token address (ignored if isEth is true).
     * @return auctionAddress The address of the newly deployed auction proxy.
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration,
        bool isEth,
        address paymentToken
    ) external returns (address auctionAddress) {
        // Only the NFT owner can start an auction
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "AuctionFactory: not NFT owner");
        
        // Ensure no existing auction for this NFT
        require(auctionOfToken[tokenId] == address(0), "AuctionFactory: auction already exists");

        // --- Deploy EIP-1167 Minimal Proxy via CREATE2 ---
        bytes memory initCode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", // Proxy preamble
            address(nftAuctionImplementation),               // Implementation address (20 bytes)
            hex"5af43d82803e903d91602b57fd5bf3"             // Proxy postamble
        );

        // Use salt = 0 (uniqueness guaranteed by tokenId context)
        assembly {
            auctionAddress := create2(0, add(initCode, 0x20), mload(initCode), 0)
        }
        require(auctionAddress != address(0), "AuctionFactory: CREATE2 failed");

        // Initialize the proxy
        NftAuction(auctionAddress).initialize(
            msg.sender,           // seller
            nftContract,
            tokenId,
            startingPrice,
            duration,
            isEth,
            paymentToken,
            ethUsdFeed,
            erc20UsdFeed
        );

        // Record the auction
        auctionOfToken[tokenId] = auctionAddress;
        allAuctions.push(auctionAddress);

        emit AuctionCreated(auctionAddress, tokenId);
        return auctionAddress;
    }

    /**
     * @dev Disables batch upgrade for security reasons.
     *      Upgrades should be handled per-auction if needed.
     */
    function upgradeAllAuctions(address newImplementation) external onlyOwner {
        revert("AuctionFactory: batch upgrade disabled for safety");
    }
}