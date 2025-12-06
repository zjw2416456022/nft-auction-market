// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract NFT is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIdCounter;

    string private _baseTokenURI;

    
    constructor() ERC721("JaredNFT", "JNFT") {}

   
    function mint(address to) external onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    /**
     * @dev 返回指定 token ID 对应的元数据 URI。
     * 如果设置了 _baseTokenURI，则返回：_baseTokenURI + tokenId。
     * 例如：_baseTokenURI = "https://example.com/nft/", tokenId = 5 → "https://example.com/nft/5"
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, IERC721Metadata)
        returns (string memory)
    {
        require(_exists(tokenId), unicode"NFT: 查询的 NFT 不存在");
        if (bytes(_baseTokenURI).length == 0) {
            return "";
        }
        return string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId)));
    }

    /**
     * @dev 设置所有 NFT 共用的基础 URI。
     * 所有者可以在任何时候更新此 URI。
     *
     * @param newBaseURI 新的基础 URI（通常以 '/' 结尾）
     */
    function setBaseTokenURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    // ========== 以下为继承冲突所需的重写函数 ==========

    /**
     * @dev 在每次代币转移前调用（用于维护 Enumerable 索引）。
     */
    function    (
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /**
     * @dev 声明合约支持的接口（用于兼容性检查）。
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}