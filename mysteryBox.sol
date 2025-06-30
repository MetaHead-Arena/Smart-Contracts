// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/IERC20.sol";

interface IPlayerNFT {
    function mintPlayer(address to, uint playerType, uint256 index) external;
    function totalURIs(uint playerType) external view returns (uint256);
}



contract MysteryBox is ConfirmedOwner , VRFConsumerBaseV2Plus {
    IERC20 public gameToken;
    IPlayerNFT public playerNFT;
    
    // Events for The Graph indexing
    event NewBox(address indexed buyer, uint256 indexed boxType);
    event BoxOpened(address indexed opener, uint256 indexed requestId, uint256 playerType, uint256 playerIndex);
    
    // Add mapping to store box opening results (packed: playerType << 8 | playerIndex)
    mapping(uint256 => uint256) public boxResults; // requestId => packed result
    
    // numOfBox [address] [type of box] = num of boxes 
    mapping(address => mapping(uint => uint)) public numOfBox;
    mapping(uint256 => address) public requestToSender;
    mapping(uint256 => uint)    public requestToBoxType;

    uint256[] public boxPrice = [10 * 1e18 , 50 * 1e18 , 100 * 1e18];// ToDo change

    bytes32 public keyHash;
    uint256 public s_subscriptionId;
    uint32  public callbackGasLimit = 500000;
    uint16  public requestConfirmations = 1;
    uint32  public numWords = 2;

    constructor(
        address _gameToken,
        address _playerNFT,

        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subId
        ) VRFConsumerBaseV2Plus(_vrfCoordinator)  {
        gameToken = IERC20(_gameToken);
        playerNFT = IPlayerNFT(_playerNFT);
        keyHash = _keyHash;
        s_subscriptionId = _subId;
    }
    address public GameEngineContract;
    
    function setGameEngineContract(address _GameEngineContract) external onlyOwner {
        GameEngineContract=_GameEngineContract;
    }

    function buyBox(uint boxType) external {
        require(boxType < 3, "Invalid box type");
        require(gameToken.balanceOf(msg.sender) >= boxPrice[boxType], "Not enough balance");
        require(gameToken.transferFrom(msg.sender, address(this), boxPrice[boxType]), "Transfer failed");

        numOfBox[msg.sender][boxType]++;
        
        emit NewBox(msg.sender, boxType);
    }

    function openBox(uint boxType) external returns (uint256 requestId){
        require(boxType < 3, "Invalid box type");
        require(numOfBox[msg.sender][boxType] > 0, "You don't have any box of this type");

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
            })
        );

        requestToBoxType[requestId] = boxType;
        requestToSender[requestId] = msg.sender;
        
        return requestId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address user = requestToSender[requestId];
        uint boxType = requestToBoxType[requestId];
        
        require(numOfBox[user][boxType] > 0, "You don't have any box of this type");
        numOfBox[user][boxType]--;

        uint256 playerType; // 0=common, 1=epic, 2=legendary
        uint256 playerIndex;
        uint256 randomBox = randomWords[0] % 100;
        uint256 randomPlayer = randomWords[1] % 100;
        // Determine rarity based on box type and randomBox
        if (boxType == 0) {
            // Common Box: 80% Common, 15% Epic, 5% Legendary
            if (randomBox < 80) {
                playerType = 0; // Common
            } else if (randomBox < 95) {
                playerType = 1; // Epic
            } else {
                playerType = 2; // Legendary
            }
        } else if (boxType == 1) {
            // Epic Box: 60% Common, 30% Epic, 10% Legendary
            if (randomBox < 60) {
                playerType = 0; // Common
            } else if (randomBox < 90) {
                playerType = 1; // Epic
            } else {
                playerType = 2; // Legendary
            }
        } else if (boxType == 2) {
            // Legendary Box: 40% Common, 40% Epic, 20% Legendary
            if (randomBox < 40) {
                playerType = 0; // Common
            } else if (randomBox < 80) {
                playerType = 1; // Epic
            } else {
                playerType = 2; // Legendary
            }
        }
        
        // Get random player from the determined rarity category
        uint256 totalPlayersInCategory = playerNFT.totalURIs(playerType);
        require(totalPlayersInCategory > 0, "No players available in this category");
        
        playerIndex = randomPlayer % totalPlayersInCategory;
        
        // Mint the NFT
        playerNFT.mintPlayer(user, playerType, playerIndex);

        // Store the result (now we store both playerType and playerIndex)
        boxResults[requestId] = (playerType << 8) | playerIndex; // Pack both values
        
        emit BoxOpened(user, requestId, playerType, playerIndex);
        
        delete requestToSender[requestId];
        delete requestToBoxType[requestId];
    }

    function setBoxPrice(uint boxType,uint256 newPrice) external onlyOwner {
        boxPrice[boxType] = newPrice;
    }

    modifier onlyGameEngineContract() {
        require(msg.sender == GameEngineContract, "You aren't allowed to to this");
        _;
    }
    function rewardBox(address to , uint boxType) external onlyGameEngineContract {
        numOfBox[to][boxType]++;
        
        emit NewBox(to, boxType);
    }

    function withdrawTokens(address to) external onlyOwner {
        require(to != address(0), "Invalid address");

        uint256 balance = gameToken.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");

        bool success = gameToken.transfer(to, balance);
        require(success, "Transfer failed");
    }

    function getNumOfBox(address _address) external view returns (uint[3] memory) {
        return [numOfBox[_address][0],
                numOfBox[_address][1],
                numOfBox[_address][2]
                ];
    }
    
    // Get the result of a specific box opening by requestId
    function getBoxResult(uint256 requestId) external view returns (uint256) {
        return boxResults[requestId]; 
        // playerType  = boxResults[requestId] >> 8
        // playerIndex = boxResults[requestId] & 0xFF
    }
        
}

