// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/utils/Counters.sol";

contract PlayerNFT is ERC721, Ownable {
    address public mysteryBoxContract;

    constructor() ERC721("Head ball Player", "HBP") {}

    function setMysteryBoxContract(address _mysteryBoxContract) external onlyOwner {
        mysteryBoxContract=_mysteryBoxContract;
    }
    
    // playerNftFrq [address][tokenNum 0->9] = array of owned token of id=[tokenNum]
    mapping (address => mapping(uint=>uint[])) public playerNftFrq;
    
    mapping (uint => uint) tokenIdToUriIndex; // tokenId To player Index to handle URI
    string[] public uris=["ipfs","ipfs","ipfs","ipfs","ipfs","ipfs","ipfs","ipfs","ipfs","ipfs"]; //ToDo fill with IPFS URI

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    modifier onlyMysteryBox() {
        require(msg.sender == mysteryBoxContract, "Not authorized");
        _;
    }

    function mintPlayer(address to, uint256 uriIndex) external onlyMysteryBox{
        require(uriIndex < uris.length, "Invalid URI index");

        uint tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        tokenIdToUriIndex[tokenId] = uriIndex;
        _tokenIdCounter.increment();
        playerNftFrq[to][uriIndex].push(tokenId);
    }


    // handling playerNftFrq to be updated
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0) && to != address(0)) {
            uint256 uriIndex = tokenIdToUriIndex[tokenId];
            if (playerNftFrq[from][uriIndex].length > 0) {
            // The frontend only requests the transfer of the last element in this array
                playerNftFrq[from][uriIndex].pop();
            }

            playerNftFrq[to][uriIndex].push(tokenId);
        }
    }

    // add new player to the game
    function addNewPlayer(string memory uri) external onlyOwner {
        uris.push(uri);
    }


    // +==================+
    // | getter functions |
    // +==================+

    // handling URI with ERC721 instead of useing ERC721URIStorage
    function tokenURI(uint tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return uris[tokenIdToUriIndex[tokenId]];
    }

    // number of player
    function totalURIs() external view returns (uint256) {
        return uris.length;
    }

    

    // number of player token owned by [address owner] 0
    function getTokenCount(address owner) external view returns (uint[] memory) {
        uint[] memory counts = new uint[](uris.length);
        for (uint i = 0; i < uris.length ; i++) { 
            counts[i] = playerNftFrq[owner][i].length;
        }
        return counts;
    }
    
    // Last token ID owned for [address owner] --> used in Transfer
    function getLastTokenOf(address owner, uint playerIndex) external view returns (uint) {
        uint[] memory tokens = playerNftFrq[owner][playerIndex];
        require(tokens.length > 0, "No tokens for this player");
        return tokens[tokens.length - 1];
    }

    
}
