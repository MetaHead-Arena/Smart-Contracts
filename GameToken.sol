// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/Ownable.sol";

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract GameToken is ERC20, Ownable, CCIPReceiver {
    IRouterClient private s_router;
    LinkTokenInterface private s_linkToken;
    
    // Mirror contracts on other networks
    mapping(uint64 => address) public mirrorContracts;
    mapping(uint64 => bool) public supportedChains;
    
    // GameEngine contract for minting tokens
    address public GameEngineContract;

    // Events
    event TokensBridged(
        address indexed user, 
        uint64 indexed toChain, 
        uint256 amount,
        bytes32 messageId
    );
    event TokensReceived(
        address indexed user, 
        uint64 indexed fromChain, 
        uint256 amount,
        bytes32 messageId
    );
    event balanceChange(address indexed user, uint256 NewBalance);
    // Chain selectors
    uint64 public constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 public constant FUJI_CHAIN_SELECTOR = 14767482510784806043;

    constructor(
        address _router,
        address _link
    ) ERC20("MetaHead Arena", "MHCoin") CCIPReceiver(_router) {
        s_router = IRouterClient(_router);
        s_linkToken = LinkTokenInterface(_link);
        _transferOwnership(msg.sender);
    }

    modifier onlyGameEngineContract() {
        require(msg.sender == GameEngineContract, "You aren't allowed to mint Token");
        _;
    }


    // +------------------+
    // | bridge functions |
    // +------------------+
    function bridgeToChain(uint64 destinationChain, uint256 amount) public payable {
        require(supportedChains[destinationChain], "Chain not supported");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be greater than 0");
        require(mirrorContracts[destinationChain] != address(0), "Mirror contract not set");
        
        // Burn tokens from the user
        _burn(msg.sender, amount);
        emit balanceChange(msg.sender, balanceOf(msg.sender));
        
        // Create CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(mirrorContracts[destinationChain]),
            data: abi.encode(msg.sender, amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 300_000})
            ),
            feeToken: address(0) // Use native token for fees
        });

        // Calculate and deduct fees
        uint256 fees = s_router.getFee(destinationChain, message);
        require(msg.value >= fees, "Insufficient fee");
        
        // Send the message
        bytes32 messageId = s_router.ccipSend{value: fees}(destinationChain, message);
        
        // Refund excess fee if any
        if (msg.value > fees) {
            payable(msg.sender).transfer(msg.value - fees);
        }
        
        emit TokensBridged(msg.sender, destinationChain, amount, messageId);
    }

    function bridgeToFuji(uint256 amount) external payable {
        bridgeToChain(FUJI_CHAIN_SELECTOR, amount);
    }

    function bridgeToSepolia(uint256 amount) external payable {
        bridgeToChain(SEPOLIA_CHAIN_SELECTOR, amount);
    }

    // Receive tokens from mirror contracts on other chains
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        uint64 sourceChain = message.sourceChainSelector;
        address mirrorContract = abi.decode(message.sender, (address));
        
        require(supportedChains[sourceChain], "Source chain not supported");
        require(mirrorContract == mirrorContracts[sourceChain], "Invalid mirror sender");
        
        (address user, uint256 amount) = abi.decode(message.data, (address, uint256));
        
        // Mint tokens to the user
        _mint(user, amount);
        emit balanceChange(user, balanceOf(user));
        emit TokensReceived(user, sourceChain, amount, message.messageId);
    }

    // +------------------+
    // | setter functions |
    // +------------------+
    function setMirrorContract(uint64 chainSelector, address mirrorAddress) external onlyOwner {
        mirrorContracts[chainSelector] = mirrorAddress;
        supportedChains[chainSelector] = true;
    }

    function setGameEngineContract(address _GameEngineContract) external onlyOwner {
        GameEngineContract = _GameEngineContract;
    }

    // +--------------------+
    // | mint&Gas functions |
    // +--------------------+
    function mint(address to, uint256 amount) external onlyGameEngineContract {
        _mint(to, amount);
        emit balanceChange(to, balanceOf(to));
    }
     
        /** Only For Test **/
    function mintByOwner(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit balanceChange(to, amount);
    }

    // Fee estimation
    function estimateBridgeFees(uint64 destinationChain, uint256 amount) external view returns (uint256) {
        require(supportedChains[destinationChain], "Chain not supported");
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(mirrorContracts[destinationChain]),
            data: abi.encode(msg.sender, amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 300_000})
            ),
            feeToken: address(0)
        });
        
        return s_router.getFee(destinationChain, message);
    }

    // +------------------+
    // | getter functions |
    // +------------------+
    function getLINKBalance() external view returns (uint256) {
        return s_linkToken.balanceOf(address(this));
    }

    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawETH(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = to.call{value: balance}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
} 