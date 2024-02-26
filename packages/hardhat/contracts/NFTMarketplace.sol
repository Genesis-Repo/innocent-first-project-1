// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is IERC721Receiver, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;

    struct NFTListing {
        address owner;
        uint256 price; // in wei
        bool isForSale;
        uint256 auctionDeadline; // deadline for auction
        address highestBidder;
        uint256 highestBid;
    }

    IERC721 public nftContract;
    uint256 public feePercentage; // in basis points (1 basis point = 0.01%)
    mapping(uint256 => NFTListing) public nftListings;
    EnumerableSet.UintSet private listedNFTs;

    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTAuctionListed(address indexed seller, uint256 indexed tokenId, uint256 startingPrice, uint256 deadline);
    event NFTBidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event NFTAuctionEnded(uint256 indexed tokenId, address indexed seller, address indexed winner, uint256 winningBid);
    event NFTSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);

    constructor(address _nftContract, uint256 _feePercentage) {
        nftContract = IERC721(_nftContract);
        feePercentage = _feePercentage;
    }

    function listNFT(uint256 tokenId, uint256 price) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");
        
        nftListings[tokenId] = NFTListing(msg.sender, price, true, 0, address(0), 0);
        listedNFTs.add(tokenId);

        emit NFTListed(msg.sender, tokenId, price);
    }

    function listNFTAuction(uint256 tokenId, uint256 startingPrice, uint256 duration) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");

        uint256 auctionDeadline = block.timestamp + duration;
        nftListings[tokenId] = NFTListing(msg.sender, startingPrice, false, auctionDeadline, address(0), 0);
        listedNFTs.add(tokenId);

        emit NFTAuctionListed(msg.sender, tokenId, startingPrice, auctionDeadline);
    }

    function placeBid(uint256 tokenId) external payable {
        require(nftListings[tokenId].auctionDeadline > 0, "NFT is not in auction");

        require(msg.value > nftListings[tokenId].highestBid, "Bid amount is lower than the current highest bid");

        address previousHighestBidder = nftListings[tokenId].highestBidder;
        uint256 previousHighestBid = nftListings[tokenId].highestBid;

        nftListings[tokenId].highestBidder = msg.sender;
        nftListings[tokenId].highestBid = msg.value;

        if (previousHighestBidder != address(0)) {
            payable(previousHighestBidder).transfer(previousHighestBid);
        }

        emit NFTBidPlaced(tokenId, msg.sender, msg.value);
    }

    function endAuction(uint256 tokenId) external {
        require(nftListings[tokenId].auctionDeadline > 0, "NFT is not in auction");
        require(block.timestamp >= nftListings[tokenId].auctionDeadline, "Auction is still ongoing");

        address seller = nftListings[tokenId].owner;
        address winner = nftListings[tokenId].highestBidder;
        uint256 winningBid = nftListings[tokenId].highestBid;

        uint256 feeAmount = winningBid.mul(feePercentage).div(10000);
        uint256 sellerAmount = winningBid.sub(feeAmount);

        payable(seller).transfer(sellerAmount);
        nftContract.safeTransferFrom(seller, winner, tokenId);

        delete nftListings[tokenId];
        listedNFTs.remove(tokenId);

        emit NFTAuctionEnded(tokenId, seller, winner, winningBid);
    }

    function unlistNFT(uint256 tokenId) external {
        require(nftListings[tokenId].owner == msg.sender, "Not the owner of the listing");

        delete nftListings[tokenId];
        listedNFTs.remove(tokenId);

        emit NFTUnlisted(tokenId);
    }

    function buyNFT(uint256 tokenId) external payable nonReentrant {
        require(nftListings[tokenId].isForSale, "NFT not for sale");
        require(msg.value >= nftListings[tokenId].price, "Insufficient funds");

        address seller = nftListings[tokenId].owner;
        uint256 salePrice = nftListings[tokenId].price;
        uint256 feeAmount = salePrice.mul(feePercentage).div(10000);

        uint256 sellerAmount = salePrice.sub(feeAmount);

        payable(seller).transfer(sellerAmount);

        nftContract.safeTransferFrom(seller, msg.sender, tokenId);
        delete nftListings[tokenId];
        listedNFTs.remove(tokenId);

        emit NFTSold(tokenId, seller, msg.sender, salePrice);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}