// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/IERC20.sol";

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

interface IMysteryBox {
    function rewardBox(address to, uint boxType) external;
}

interface IGameToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract GameEngine is ConfirmedOwner, FunctionsClient, VRFConsumerBaseV2Plus {
    using FunctionsRequest for FunctionsRequest.Request;
    
    event MatchProcessed(address indexed player, uint256 matchID, bool won, uint256 boxIndex);
    event MatchRequestSent(address indexed player, uint256 matchID, bytes32 requestId);
    event MatchRequestFailed(address indexed player, uint256 matchID, string error);
    
    IGameToken public gameToken;
    IMysteryBox public mysteryBox;

    mapping(uint => bool) public processedMatches;


    // Chainlink Functions
    uint64 public s_subscriptionId;
    bytes32 public donID;
    string private apiUrl; // game server API URL
    uint32 public callbackGasLimit = 300000;

    // Chainlink VRF
    bytes32 public keyHash;
    uint256 public s_vrfSubscriptionId;
    uint32 public vrfCallbackGasLimit = 200000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;

    // Request tracking
    mapping(bytes32 => address) public requestToPlayer;
    mapping(bytes32 => uint256) public requestToMatchID;
    mapping(uint256 => bytes32) public vrfRequestToFunctionsRequest;

    struct MatchResult {
        address player;
        uint256 matchID;
        bool won;
        uint256 gainXP;
        uint256 gainCoins;
    }
    mapping(bytes32 => MatchResult) public pendingMatches;

    
    mapping(address => uint) public playerXP;


    constructor(
        address _token, 
        address _box,

        // Chainlink API
        address _functionsRouter,
        bytes32 _donID,
        uint64 _subscriptionId,

        // Chainlink VRF
        address _vrfCoordinator,
        uint256 _vrfSubscriptionId,
        bytes32 _keyHash,

        // server api url
        string memory _apiUrl
    ) FunctionsClient(_functionsRouter) VRFConsumerBaseV2Plus(_vrfCoordinator){
        gameToken = IGameToken(_token);
        mysteryBox = IMysteryBox(_box);

        s_subscriptionId = _subscriptionId;
        s_vrfSubscriptionId = _vrfSubscriptionId;
        donID = _donID;
        keyHash = _keyHash;
        apiUrl = _apiUrl;
    }

    

    function reportMatch(address player, uint256 matchID) external {
        require(player != address(0), "Invalid player address");
        
        require(!processedMatches[matchID], "Match already processed");
        processedMatches[matchID] = true;
    

        string memory JS_SOURCE = 
            "const matchID = args[0]; "
            "const apiResponse = await Functions.makeHttpRequest({ "
            "url: args[1] + matchID, "
            "method: 'GET' "
            "}); "
            "if (apiResponse.error) throw Error('Request failed'); "
            "return Functions.encodeUint256(apiResponse.data.won ? 1 : 0);";
    
        string[] memory args = new string[](2);
        args[0] = uint2str(matchID);
        args[1] = apiUrl;
        
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(JS_SOURCE);

        req.setArgs(args);
        
        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            s_subscriptionId,
            callbackGasLimit,
            donID
        );
        
        requestToPlayer[requestId] = player;
        requestToMatchID[requestId] = matchID;

        emit MatchRequestSent(player, matchID, requestId);
    }
    
    // API response
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (err.length > 0) {
            emit MatchRequestFailed(requestToPlayer[requestId], requestToMatchID[requestId], string(err));
            delete requestToPlayer[requestId];
            delete requestToMatchID[requestId];
            processedMatches[requestToMatchID[requestId]] = false;
            return;
        }
        
        address player = requestToPlayer[requestId];
        uint256 matchID = requestToMatchID[requestId];
        
        uint256 wonValue = abi.decode(response, (uint256));
        bool won = (wonValue == 1);
        
        uint256 gainXP = won ? 100 : 30; // ToDo change
        uint256 gainCoins = won ? 20 * 1e18 : 5 * 1e18;  // ToDo change
        
        pendingMatches[requestId] = MatchResult({
            player: player,
            matchID: matchID,
            won: won,
            gainXP: gainXP,
            gainCoins: gainCoins
        });
        
        uint oldLevel = getLevelFromXP(playerXP[player]);
        playerXP[player] += gainXP;
        uint curLevel = getLevelFromXP(playerXP[player]);
        
        gameToken.mint(player, gainCoins);
        
        // Mystery Box reward
        if (curLevel > oldLevel) {
            uint256 vrfRequestId = s_vrfCoordinator.requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                    keyHash: keyHash,
                    subId: s_vrfSubscriptionId,
                    requestConfirmations: requestConfirmations,
                    callbackGasLimit: vrfCallbackGasLimit,
                    numWords: numWords,
                    extraArgs: VRFV2PlusClient._argsToBytes(
                        VRFV2PlusClient.ExtraArgsV1({
                            nativePayment: false
                        })
                    )
                })
            );
            vrfRequestToFunctionsRequest[vrfRequestId] = requestId;
        }
        
        delete requestToPlayer[requestId];
        delete requestToMatchID[requestId];
    }


    // VRF response
    function fulfillRandomWords(uint256 vrfRequestId, uint256[] calldata randomWords) internal override {
        bytes32 functionsRequestId = vrfRequestToFunctionsRequest[vrfRequestId];
        MatchResult memory matchData = pendingMatches[functionsRequestId];
        
        if (matchData.player != address(0)) {
            uint256 boxIndex = randomWords[0] % 3; // 0, 1, 2
            mysteryBox.rewardBox(matchData.player, boxIndex);
            
            emit MatchProcessed(matchData.player, matchData.matchID, matchData.won, boxIndex);
        }
        
        delete vrfRequestToFunctionsRequest[vrfRequestId];
        delete pendingMatches[functionsRequestId];
    }

    // +==================+
    // | getter functions |
    // +==================+

    function getPlayerXP(address _player) public view returns (uint) {
        return playerXP[_player];
    }

    function getLevelFromXP(uint256 totalXP) public pure returns (uint256) {
       if (totalXP < 100) return 0;
       if (totalXP == 100) return 1;

       uint256 left = 1;
       uint256 right = 255;
    
       while (left < right) {
           uint256 mid = (left + right + 1) >> 1;
           uint256 requiredXP = getXPForLevel(mid);

           if (totalXP >= requiredXP) {
               left = mid;
           } else {
               right = mid - 1;
           }
       }
    
       return left;
    }

    function getXPForLevel(uint256 level) public pure returns (uint256) {
       if (level < 1) return 0;
       return 100 * level * (100 + level) / 100;
    }

    // +==================+
    // | Helper functions |
    // +==================+

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    
    // +==================+
    // | set functions |
    // +==================+

    function setApiUrl(string memory _newUrl) external onlyOwner {
        apiUrl = _newUrl;
    }
}
