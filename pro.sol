//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFTMarketplace is ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    //_tokenIds variable has the most recent minted tokenId
    Counters.Counter private _tokenIds;
    //Keeps track of the number of items sold on the marketplace
    Counters.Counter public _itemsSold;
    //The fee charged by the marketplace to be allowed to list an NFT
    uint256 listPrice = 0.01 ether;

    uint256 onSaleCount;
    //The structure to store info about a listed token
    struct ListedToken {
        uint256 tokenId;
        address payable owner;
        address payable seller;
        uint256 price;
        bool currentlyListed;
    }

    //the event emitted when a token is successfully listed
    event TokenListedSuccess(
        uint256 indexed tokenId,
        address owner,
        address seller,
        uint256 price,
        bool currentlyListed
    );

    event Sold(uint256 tokenId, address seller, address owner, uint256 price);

    //This mapping maps tokenId to token info and is helpful when retrieving details about a tokenId
    mapping(uint256 => ListedToken) private idToListedToken;

    // keeps track of tokens owned by a wallet
    mapping(address => uint256[]) private ownedTokens;

    constructor() ERC721("NFTMarketplace", "NFTM") {}

    modifier exist(uint256 tokenId) {
        require(_exists(tokenId), "Query for non existent token");
        _;
    }

    modifier checkPrice(uint256 price) {
        // makes sure that the price is at least twice the price of the listing fee
        // to make sure that seller can pay listing fee when token is sold
        require(price >= (listPrice * 2), "Invalid price");
        _;
    }

    function updateListPrice(uint256 _listPrice) public payable onlyOwner {
        require(_listPrice > 0, "Invalid listing price");
        listPrice = _listPrice;
    }

    function getListPrice() public view returns (uint256) {
        return listPrice;
    }

    function getLatestIdToListedToken()
        public
        view
        returns (ListedToken memory)
    {
        return idToListedToken[_tokenIds.current()];
    }

    function getListedTokenForId(uint256 tokenId)
        public
        view
        exist(tokenId)
        returns (ListedToken memory)
    {
        return idToListedToken[tokenId];
    }

    function getCurrentToken() public view returns (uint256) {
        return _tokenIds.current();
    }

    //The first time a token is created, it is listed here
    function createToken(string memory _tokenURI, uint256 price)
        public
        payable
        checkPrice(price)
        returns (uint256)
    {
        require(bytes(_tokenURI).length > 0, "Invalid URI");
        uint256 newTokenId = _tokenIds.current();
        _tokenIds.increment();
        ownedTokens[msg.sender].push(newTokenId);
        //Mint the NFT with tokenId newTokenId to the address who called createToken
        _safeMint(msg.sender, newTokenId);

        //Map the tokenId to the tokenURI (which is an IPFS URL with the NFT metadata)
        _setTokenURI(newTokenId, _tokenURI);

        //Helper function to update Global variables and emit an event
        createListedToken(newTokenId, price);

        return newTokenId;
    }

    function createListedToken(uint256 tokenId, uint256 price)
        private
        exist(tokenId)
        checkPrice(price)
    {
        //Update the mapping of tokenId's to Token details, useful for retrieval functions
        idToListedToken[tokenId] = ListedToken(
            tokenId,
            payable(address(this)),
            payable(ownerOf(tokenId)),
            price,
            true
        );
        onSaleCount++;

        _transfer(msg.sender, address(this), tokenId);
        //Emit the event for successful transfer. The frontend parses this message and updates the end user
        emit TokenListedSuccess(
            tokenId,
            address(this),
            msg.sender,
            price,
            true
        );
    }

    //This will return all the NFTs currently listed to be sold on the marketplace
    function getAllNFTs() public view returns (ListedToken[] memory) {
        uint256 nftCount = _tokenIds.current();
        ListedToken[] memory tokens = new ListedToken[](onSaleCount);
        uint256 currentIndex = 0;

        // loops through idTOListedToken and assigns only tokens available for sale
        // to ListedTokens
        for (uint256 i = 0; i < nftCount; i++) {
            if (idToListedToken[i].currentlyListed) {
                tokens[currentIndex] = idToListedToken[i];
                currentIndex += 1;
            }
        }
        //the array 'tokens' has the list of all NFTs in the marketplace
        return tokens;
    }

    //Returns all the NFTs that the current user is owner or seller in
    function getMyNFTs() public view returns (ListedToken[] memory) {
        uint256 range = ownedTokens[msg.sender].length;
        ListedToken[] memory tokens = new ListedToken[](range);
        uint256 index = 0;
        for (uint256 i = 0; i < range; i++) {
            if (ownerOf(ownedTokens[msg.sender][i]) == msg.sender) {
                tokens[index] = idToListedToken[ownedTokens[msg.sender][i]];
                index += 1;
            }
        }
        return tokens;
    }

    // allows user to relist Token
    function relistToken(uint256 tokenId, uint256 price)
        public
        exist(tokenId)
        checkPrice(price)
    {
        ListedToken storage currentListing = idToListedToken[tokenId];
        require(
            !currentListing.currentlyListed,
            "Item has already been listed"
        );
        require(
            ownerOf(tokenId) == msg.sender ||
                getApproved(tokenId) == msg.sender,
            "Unauthorized caller"
        );
        createListedToken(tokenId, price);
    }

    function claimNFT(uint256 tokenId) external exist(tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Unauthorized caller");

        delete idToListedToken[tokenId];
        _burn(tokenId);
    }

    function executeSale(uint256 tokenId) public payable {
        uint256 price = idToListedToken[tokenId].price;
        address payable seller = idToListedToken[tokenId].seller;
        require(
            msg.value == price,
            "Please submit the asking price in order to complete the purchase"
        );
        require(msg.sender != seller, "You can't buy your own token");
        require(idToListedToken[tokenId].currentlyListed, "Not listed");
        //update the details of the token
        idToListedToken[tokenId].price = 0;
        idToListedToken[tokenId].currentlyListed = false;
        idToListedToken[tokenId].owner = payable(msg.sender);
        idToListedToken[tokenId].seller = payable(address(0));
        _itemsSold.increment();
        onSaleCount--;
        ownedTokens[msg.sender].push(tokenId);
        //Actually transfer the token to the new owner
        _transfer(address(this), msg.sender, tokenId);

        // payment is made to seller
        (bool success, ) = seller.call{value: (price - listPrice)}("");
        // payment for lisitng is made to current contract owner
        require(success, "Transfer to seller failed");
        (bool sent, ) = payable(owner()).call{value: listPrice}("");
        require(sent, "Transfer for listing fee failed");
        emit Sold(tokenId, seller, msg.sender, price);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
