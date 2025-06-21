// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/IERC20.sol";

interface IPlayerNFT {
    function mintPlayer(address to, uint256 index) external;
    function totalURIs() external view returns (uint256);
}



contract MysteryBox is ConfirmedOwner , VRFConsumerBaseV2Plus {
    IERC20 public gameToken;
    IPlayerNFT public playerNFT;
    
    // numOfBox [address] [type of box] = num of boxes 
    mapping(address => mapping(uint => uint)) public numOfBox;
    mapping(uint256 => address) public requestToSender;
    mapping(uint256 => uint)    public requestToBoxType;

    uint256[] public boxPrice = [10 * 1e18 , 50 * 1e18 , 100 * 1e18];// ToDo change

    bytes32 public keyHash;
    uint256 public s_subscriptionId;
    uint32  public callbackGasLimit = 200000;
    uint16  public requestConfirmations = 3;
    uint32  public numWords = 1;

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
    }

    function openBox(uint boxType) external {
        require(boxType < 3, "Invalid box type");
        require(numOfBox[msg.sender][boxType] > 0, "You don't have any box of this type");
        numOfBox[msg.sender][boxType]--;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
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
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address user = requestToSender[requestId];
        uint boxType = requestToBoxType[requestId];
        
        uint256 index;
        uint256 randomValue = randomWords[0] % 100;
        
        if (boxType == 0) {
            // 80% Common, 15% Epic, 5% Legendary
            if (randomValue < 80) {
                // Common NFTs (index 0-4)
                index = randomValue % 5;
            } else if (randomValue < 95) {
                // Epic NFTs (index 5-7)
                index = 5 + (randomValue % 3);
            } else {
                // Legendary NFTs (index 8-9)
                index = 8 + (randomValue % 2);
            }
        } else if (boxType == 1) {
            // 60% Common, 30% Epic, 10% Legendary
            if (randomValue < 60) {
                // Common NFTs (index 0-4)
                index = randomValue % 5;
            } else if (randomValue < 90) {
                // Epic NFTs (index 5-7)
                index = 5 + (randomValue % 3);
            } else {
                // Legendary NFTs (index 8-9)
                index = 8 + (randomValue % 2);
            }
        } else if (boxType == 2) {
            // 40% Common, 40% Epic, 20% Legendary
            if (randomValue < 40) {
                // Common NFTs (index 0-4)
                index = randomValue % 5;
            } else if (randomValue < 80) {
                // Epic NFTs (index 5-7)
                index = 5 + (randomValue % 3);
            } else {
                // Legendary NFTs (index 8-9)
                index = 8 + (randomValue % 2);
            }
        }
        
        playerNFT.mintPlayer(user, index);
        
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
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        gameToken.transfer(to, amount);
    }

    function getNumOfBox(address _address) external view returns (uint[3] memory) {
        return [numOfBox[_address][0],
                numOfBox[_address][1],
                numOfBox[_address][2]
                ];
    }
}

