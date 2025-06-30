// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./PlayerAuction.sol";

contract MarketplaceFactory{
    address public  NTFaddres;
    address public gameToken;
    
    constructor(address _NTFaddres,address _gameToken){
        NTFaddres=_NTFaddres;
        gameToken=_gameToken;
    }

    event AuctionCreated(
       address indexed auctionContract,
       address indexed creator,
       uint256 nftID,
       uint256 startPrice
    );

    address[] public deployedAuctions;
    function createAuction(uint _nftID , uint _startPrice,uint _endAt) public returns (address)  {
        require(_endAt > block.timestamp, "End time must be in future");
        require(_startPrice > 0, "Start price must be greater than 0");
        
        PlayerAuction newAuction=new PlayerAuction(NTFaddres,gameToken, _nftID, _startPrice, _endAt,msg.sender);
        deployedAuctions.push(address(newAuction));
        emit AuctionCreated(address(newAuction), msg.sender, _nftID, _startPrice);

        return address(newAuction);
    }

    // +==================+
    // | getter functions |
    // +==================+
    function getDeployedAuctions()public view returns (address[] memory){
        return deployedAuctions;
    }

    function getAuctionCount() external view returns (uint256) {
        return deployedAuctions.length;
    }

    function getAuctionByIndex(uint256 index) external view returns (address) {
        require(index < deployedAuctions.length, "Index out of bounds");
        return deployedAuctions[index];
    }
}

