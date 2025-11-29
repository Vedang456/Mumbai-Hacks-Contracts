// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CarbonCreditMarketplace
 * @dev Auction-based marketplace for trading carbon credits
 */
contract CarbonCreditMarketplace is ERC1155Holder, ReentrancyGuard, Ownable {
    
    IERC1155 public carbonCreditToken;
    
    // Auction Types
    enum AuctionType {
        English,      // Price increases with bids
        Dutch,        // Price decreases over time
        FixedPrice    // Buy it now
    }
    
    enum AuctionStatus {
        Active,
        Completed,
        Cancelled
    }
    
    struct Listing {
        uint256 listingId;
        uint256 projectId;
        address seller;
        uint256 amount;
        uint256 startingPrice;
        uint256 reservePrice;
        uint256 currentPrice;
        address highestBidder;
        uint256 startTime;
        uint256 endTime;
        AuctionType auctionType;
        AuctionStatus status;
    }
    
    struct DutchAuctionParams {
        uint256 priceDecrement;
        uint256 decrementInterval;
    }
    
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }
    
    struct RFP {
        uint256 rfpId;
        address buyer;
        uint256 desiredAmount;
        uint256 maxPricePerCredit;
        uint256 projectCategory;
        string requirements;
        uint256 deadline;
        bool isFulfilled;
    }
    
    // State variables
    uint256 private _listingIdCounter;
    uint256 private _rfpIdCounter;
    uint256 public platformFeePercentage = 250; // 2.5% (basis points)
    uint256 public minBidIncrement = 0.01 ether;
    
    // Mappings
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => DutchAuctionParams) public dutchParams;
    mapping(uint256 => Bid[]) public listingBids;
    mapping(uint256 => RFP) public rfps;
    mapping(address => uint256[]) public sellerListings;
    mapping(address => uint256[]) public buyerRFPs;
    mapping(address => uint256) public pendingWithdrawals;
    
    // Events
    event ListingCreated(
        uint256 indexed listingId,
        uint256 indexed projectId,
        address indexed seller,
        uint256 amount,
        uint256 startingPrice,
        AuctionType auctionType
    );
    
    event BidPlaced(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );
    
    event AuctionCompleted(
        uint256 indexed listingId,
        address indexed winner,
        uint256 finalPrice,
        uint256 amount
    );
    
    event AuctionCancelled(
        uint256 indexed listingId,
        address indexed seller
    );
    
    event FixedPriceSale(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount,
        uint256 price
    );
    
    event RFPCreated(
        uint256 indexed rfpId,
        address indexed buyer,
        uint256 desiredAmount,
        uint256 maxPrice
    );
    
    event RFPFulfilled(
        uint256 indexed rfpId,
        uint256 indexed listingId,
        address indexed seller
    );
    
    constructor(address _carbonCreditToken) Ownable(msg.sender) {
        carbonCreditToken = IERC1155(_carbonCreditToken);
    }
    
    /**
     * @dev Create a new listing (English Auction)
     */
    function createEnglishAuction(
        uint256 _projectId,
        uint256 _amount,
        uint256 _startingPrice,
        uint256 _reservePrice,
        uint256 _duration
    ) external returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_startingPrice > 0, "Starting price must be greater than 0");
        require(_duration >= 1 hours, "Duration must be at least 1 hour");
        require(
            carbonCreditToken.balanceOf(msg.sender, _projectId) >= _amount,
            "Insufficient balance"
        );
        
        _listingIdCounter++;
        uint256 newListingId = _listingIdCounter;
        
        listings[newListingId] = Listing({
            listingId: newListingId,
            projectId: _projectId,
            seller: msg.sender,
            amount: _amount,
            startingPrice: _startingPrice,
            reservePrice: _reservePrice,
            currentPrice: _startingPrice,
            highestBidder: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            auctionType: AuctionType.English,
            status: AuctionStatus.Active
        });
        
        sellerListings[msg.sender].push(newListingId);
        
        // Transfer credits to marketplace (escrow)
        carbonCreditToken.safeTransferFrom(
            msg.sender,
            address(this),
            _projectId,
            _amount,
            ""
        );
        
        emit ListingCreated(
            newListingId,
            _projectId,
            msg.sender,
            _amount,
            _startingPrice,
            AuctionType.English
        );
        
        return newListingId;
    }
    
    /**
     * @dev Create a Dutch auction (descending price)
     */
    function createDutchAuction(
        uint256 _projectId,
        uint256 _amount,
        uint256 _startingPrice,
        uint256 _reservePrice,
        uint256 _priceDecrement,
        uint256 _decrementInterval,
        uint256 _duration
    ) external returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_startingPrice > _reservePrice, "Starting price must exceed reserve");
        require(_priceDecrement > 0, "Price decrement must be positive");
        require(_decrementInterval >= 5 minutes, "Interval too short");
        require(
            carbonCreditToken.balanceOf(msg.sender, _projectId) >= _amount,
            "Insufficient balance"
        );
        
        _listingIdCounter++;
        uint256 newListingId = _listingIdCounter;
        
        listings[newListingId] = Listing({
            listingId: newListingId,
            projectId: _projectId,
            seller: msg.sender,
            amount: _amount,
            startingPrice: _startingPrice,
            reservePrice: _reservePrice,
            currentPrice: _startingPrice,
            highestBidder: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            auctionType: AuctionType.Dutch,
            status: AuctionStatus.Active
        });
        
        dutchParams[newListingId] = DutchAuctionParams({
            priceDecrement: _priceDecrement,
            decrementInterval: _decrementInterval
        });
        
        sellerListings[msg.sender].push(newListingId);
        
        carbonCreditToken.safeTransferFrom(
            msg.sender,
            address(this),
            _projectId,
            _amount,
            ""
        );
        
        emit ListingCreated(
            newListingId,
            _projectId,
            msg.sender,
            _amount,
            _startingPrice,
            AuctionType.Dutch
        );
        
        return newListingId;
    }
    
    /**
     * @dev Create fixed price listing
     */
    function createFixedPriceListing(
        uint256 _projectId,
        uint256 _amount,
        uint256 _price
    ) external returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");
        require(
            carbonCreditToken.balanceOf(msg.sender, _projectId) >= _amount,
            "Insufficient balance"
        );
        
        _listingIdCounter++;
        uint256 newListingId = _listingIdCounter;
        
        listings[newListingId] = Listing({
            listingId: newListingId,
            projectId: _projectId,
            seller: msg.sender,
            amount: _amount,
            startingPrice: _price,
            reservePrice: _price,
            currentPrice: _price,
            highestBidder: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + 365 days,
            auctionType: AuctionType.FixedPrice,
            status: AuctionStatus.Active
        });
        
        sellerListings[msg.sender].push(newListingId);
        
        carbonCreditToken.safeTransferFrom(
            msg.sender,
            address(this),
            _projectId,
            _amount,
            ""
        );
        
        emit ListingCreated(
            newListingId,
            _projectId,
            msg.sender,
            _amount,
            _price,
            AuctionType.FixedPrice
        );
        
        return newListingId;
    }
    
    /**
     * @dev Place bid on English auction
     */
    function placeBid(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.status == AuctionStatus.Active, "Auction not active");
        require(block.timestamp <= listing.endTime, "Auction ended");
        require(
            listing.auctionType == AuctionType.English,
            "Not an English auction"
        );
        require(msg.sender != listing.seller, "Seller cannot bid");
        require(
            msg.value >= listing.currentPrice + minBidIncrement,
            "Bid too low"
        );
        
        // Refund previous highest bidder
        if (listing.highestBidder != address(0)) {
            pendingWithdrawals[listing.highestBidder] += listing.currentPrice;
        }
        
        // Update listing
        listing.highestBidder = msg.sender;
        listing.currentPrice = msg.value;
        
        // Record bid
        listingBids[_listingId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp
        }));
        
        emit BidPlaced(_listingId, msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Buy at current Dutch auction price
     */
    function buyDutchAuction(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.status == AuctionStatus.Active, "Auction not active");
        require(block.timestamp <= listing.endTime, "Auction ended");
        require(
            listing.auctionType == AuctionType.Dutch,
            "Not a Dutch auction"
        );
        
        uint256 currentPrice = getCurrentDutchPrice(_listingId);
        require(msg.value >= currentPrice, "Insufficient payment");
        
        // Complete the auction
        _completeAuction(_listingId, msg.sender, currentPrice);
        
        // Refund excess
        if (msg.value > currentPrice) {
            pendingWithdrawals[msg.sender] += (msg.value - currentPrice);
        }
    }
    
    /**
     * @dev Buy at fixed price
     */
    function buyFixedPrice(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.status == AuctionStatus.Active, "Listing not active");
        require(
            listing.auctionType == AuctionType.FixedPrice,
            "Not a fixed price listing"
        );
        require(msg.value >= listing.currentPrice, "Insufficient payment");
        
        uint256 price = listing.currentPrice;
        
        _completeAuction(_listingId, msg.sender, price);
        
        // Refund excess
        if (msg.value > price) {
            pendingWithdrawals[msg.sender] += (msg.value - price);
        }
        
        emit FixedPriceSale(
            _listingId,
            msg.sender,
            listing.amount,
            price
        );
    }
    
    /**
     * @dev Finalize English auction
     */
    function finalizeAuction(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.status == AuctionStatus.Active, "Auction not active");
        require(block.timestamp > listing.endTime, "Auction still ongoing");
        require(
            listing.auctionType == AuctionType.English,
            "Not an English auction"
        );
        
        if (listing.highestBidder == address(0) || 
            listing.currentPrice < listing.reservePrice) {
            // No bids or reserve not met - cancel and return to seller
            _cancelAuction(_listingId);
        } else {
            // Complete the auction
            _completeAuction(
                _listingId,
                listing.highestBidder,
                listing.currentPrice
            );
        }
    }
    
    /**
     * @dev Internal function to complete auction
     */
    function _completeAuction(
        uint256 _listingId,
        address _winner,
        uint256 _finalPrice
    ) internal {
        Listing storage listing = listings[_listingId];
        
        // Calculate platform fee
        uint256 platformFee = (_finalPrice * platformFeePercentage) / 10000;
        uint256 sellerProceeds = _finalPrice - platformFee;
        
        // Transfer credits to winner
        carbonCreditToken.safeTransferFrom(
            address(this),
            _winner,
            listing.projectId,
            listing.amount,
            ""
        );
        
        // Transfer payment to seller
        pendingWithdrawals[listing.seller] += sellerProceeds;
        pendingWithdrawals[owner()] += platformFee;
        
        // Update listing status
        listing.status = AuctionStatus.Completed;
        listing.highestBidder = _winner;
        
        emit AuctionCompleted(_listingId, _winner, _finalPrice, listing.amount);
    }
    
    /**
     * @dev Cancel listing (only seller, before any bids)
     */
    function cancelListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(msg.sender == listing.seller, "Only seller can cancel");
        require(listing.status == AuctionStatus.Active, "Listing not active");
        require(
            listing.auctionType != AuctionType.English || 
            listing.highestBidder == address(0),
            "Cannot cancel auction with bids"
        );
        
        _cancelAuction(_listingId);
    }
    
    /**
     * @dev Internal cancel function
     */
    function _cancelAuction(uint256 _listingId) internal {
        Listing storage listing = listings[_listingId];
        
        // Return credits to seller
        carbonCreditToken.safeTransferFrom(
            address(this),
            listing.seller,
            listing.projectId,
            listing.amount,
            ""
        );
        
        listing.status = AuctionStatus.Cancelled;
        
        emit AuctionCancelled(_listingId, listing.seller);
    }
    
    /**
     * @dev Create RFP (Request for Proposal)
     */
    function createRFP(
        uint256 _desiredAmount,
        uint256 _maxPricePerCredit,
        uint256 _projectCategory,
        string memory _requirements,
        uint256 _deadline
    ) external returns (uint256) {
        require(_desiredAmount > 0, "Amount must be positive");
        require(_maxPricePerCredit > 0, "Price must be positive");
        require(_deadline > block.timestamp, "Deadline must be in future");
        
        _rfpIdCounter++;
        uint256 newRfpId = _rfpIdCounter;
        
        rfps[newRfpId] = RFP({
            rfpId: newRfpId,
            buyer: msg.sender,
            desiredAmount: _desiredAmount,
            maxPricePerCredit: _maxPricePerCredit,
            projectCategory: _projectCategory,
            requirements: _requirements,
            deadline: _deadline,
            isFulfilled: false
        });
        
        buyerRFPs[msg.sender].push(newRfpId);
        
        emit RFPCreated(newRfpId, msg.sender, _desiredAmount, _maxPricePerCredit);
        
        return newRfpId;
    }
    
    /**
     * @dev Withdraw accumulated funds
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        pendingWithdrawals[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @dev Get current price for Dutch auction
     */
    function getCurrentDutchPrice(uint256 _listingId) public view returns (uint256) {
        Listing memory listing = listings[_listingId];
        
        if (listing.auctionType != AuctionType.Dutch) {
            return listing.currentPrice;
        }
        
        DutchAuctionParams memory params = dutchParams[_listingId];
        
        uint256 elapsed = block.timestamp - listing.startTime;
        uint256 intervals = elapsed / params.decrementInterval;
        uint256 totalDecrement = intervals * params.priceDecrement;
        
        if (totalDecrement >= listing.startingPrice - listing.reservePrice) {
            return listing.reservePrice;
        }
        
        return listing.startingPrice - totalDecrement;
    }
    
    /**
     * @dev Get all listings by seller
     */
    function getSellerListings(address _seller) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sellerListings[_seller];
    }
    
    /**
     * @dev Get bid history for a listing
     */
    function getListingBids(uint256 _listingId) 
        external 
        view 
        returns (Bid[] memory) 
    {
        return listingBids[_listingId];
    }
    
    /**
     * @dev Get listing details
     */
    function getListing(uint256 _listingId) 
        external 
        view 
        returns (Listing memory) 
    {
        return listings[_listingId];
    }
    
    /**
     * @dev Get Dutch auction parameters
     */
    function getDutchParams(uint256 _listingId)
        external
        view
        returns (DutchAuctionParams memory)
    {
        return dutchParams[_listingId];
    }
    
    /**
     * @dev Update platform fee (only owner)
     */
    function setPlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee too high"); // Max 10%
        platformFeePercentage = _newFee;
    }
    
    /**
     * @dev Update minimum bid increment (only owner)
     */
    function setMinBidIncrement(uint256 _newIncrement) external onlyOwner {
        require(_newIncrement > 0, "Increment must be positive");
        minBidIncrement = _newIncrement;
    }
}