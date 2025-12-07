// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract NFT is ERC721Enumerable, Ownable {
    uint256 private _nextTokenId; // 自动递增的 tokenId，从 0 开始
    string private _tokenURI;
    
    constructor() ERC721("JaredNFT", "JNFT") Ownable(msg.sender) {}


    function mint(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId); // 必须用 safeMint！防止 NFT 永久丢失
        return tokenId;
    }

  
    function tokenURI(uint256 /* tokenId */) 
        public view override returns (string memory) 
    {
        return _tokenURI;
    }


    function setTokenURI(string memory newTokenURI) external onlyOwner {
        _tokenURI = newTokenURI;
    }

    
}