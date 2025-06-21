// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IPlayerNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract PlayerAuction{
    struct AuctionData {
        uint startPrice;
        uint maxPrice;
        uint endAt;
        bool finished;
        bool started;
        address winner;
        uint256 nftID;
    }    
    AuctionData public auctionData;

    address public manager;
    mapping(address=>uint) public balances;

    IERC20 public gameToken;
    IPlayerNFT public nft;

    event NewEnter(address indexed user, uint amount);
    event AuctionFinished(address user, uint amount);
    event Withdraw(address user, uint amount);

    constructor (address NTFaddres,address _gameToken,uint _nftID , uint _startPrice,uint _endAt,address msgSender){
        nft=IPlayerNFT(NTFaddres);
        gameToken=IERC20(_gameToken);
        manager = msgSender;
        auctionData.nftID=_nftID;
        auctionData.startPrice = _startPrice;
        auctionData.endAt = _endAt;
        auctionData.maxPrice=_startPrice;
        
        require(nft.ownerOf(_nftID) == msgSender, "You must own the NFT");
    }

    modifier onlyOwner() {
        require(msg.sender == manager, "You aren't the Owner");
        _;
    }

    // start after approve contract in Frontend
    function start() external onlyOwner{
        nft.safeTransferFrom(manager, address(this),auctionData.nftID);
        auctionData.started=true;
    }

    function bid(uint amount ) external  {
        require(auctionData.started , "Auction not started yet");
        require(block.timestamp < auctionData.endAt, "Auction has ended");
      
        // handling If the owner ends the auction before [auctionData.endAt]
        require(!auctionData.finished, "Auction already finished");

        uint256 newTotal = balances[msg.sender] + amount;

        require(newTotal > auctionData.maxPrice);
    
        // approve contract first in Frontend 
        gameToken.transferFrom(msg.sender, address(this), amount);
    
        balances[msg.sender]=newTotal;
        auctionData.maxPrice=newTotal;
        auctionData.winner=msg.sender;
        emit NewEnter(msg.sender, amount);
    }

    function end() external {
        require(auctionData.started , "Auction not started yet");
        require(
            (block.timestamp >= auctionData.endAt) || (msg.sender == manager),
            "Auction is not finished yet"
        );
        require(!auctionData.finished, "Auction is already finished");
        require(msg.sender == manager || msg.sender == auctionData.winner);

        auctionData.finished = true;
        if(auctionData.winner!=address(0)){
            nft.safeTransferFrom(address(this), auctionData.winner, auctionData.nftID);
            
            gameToken.transfer(manager, auctionData.maxPrice);

            emit AuctionFinished(auctionData.winner, auctionData.maxPrice);
        }
        else {
            nft.safeTransferFrom(address(this), manager, auctionData.nftID);
        }
    }
    function withdraw()external  {
        // user can withdraw his money if he is not the winner
        // even if the auction is in progress
        
        require(auctionData.started , "Auction not started yet");
        require(balances[msg.sender]>0); 
        require(msg.sender != auctionData.winner); 
        
        uint amount = balances[msg.sender];
        balances[msg.sender]=0;

        require(gameToken.transfer(msg.sender, amount), "Transfer failed");
        emit Withdraw(msg.sender,amount);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // +==================+
    // | getter functions |
    // +==================+
    function getAuctionInfo() external view returns (AuctionData memory) {
        return auctionData;
    }

    function getUserBalance(address user) external view returns (uint) {
        return balances[user];
    }
}
