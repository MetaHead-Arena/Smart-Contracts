// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/utils/Counters.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract PlayerNFT is ERC721, Ownable, CCIPReceiver {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    IRouterClient private s_router;
    
    // Mirror contracts - Sepolia and Fuji
    address public sepoliaMirror;
    address public fujiMirror;
    
    // Original PlayerNFT functionality  
    address public mysteryBoxContract;
    mapping(address => mapping(uint => mapping(uint => uint[]))) public playerNftFrq;
    mapping(uint => uint) public tokenIdToUriIndex;
    mapping(uint => uint) public tokenIdToType;
    string[][3] public uris; // [0]-> common | [1]-> epic | [2]-> legendary
    // Events for The Graph indexing + Bridge events
    event NFTBridged(address indexed owner, uint256 indexed tokenId, uint64 indexed toChain, bytes32 messageId);
    event NFTReceived(address indexed owner, uint256 indexed newTokenId, uint64 indexed fromChain, bytes32 messageId);
    event PlayerMinted(address indexed to, uint256 indexed playerType, uint256 indexed uriIndex);
    event TokenOwnershipChanged(address indexed from, address indexed to, uint256 indexed playerType, uint256 uriIndex);
    event NewPlayerAdded(uint256 indexed playerType,uint256 indexed playerIndex, string uri);

    // Chain selectorss
    uint64 public constant SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 public constant FUJI_CHAIN_SELECTOR = 14767482510784806043;

    constructor(address _router) ERC721("Head ball Player", "HBP") CCIPReceiver(_router) {
        s_router = IRouterClient(_router);
        _transferOwnership(msg.sender);
        
        uris[0].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreiaubraqacngtzbea7ha64l4al5q7hmwisap4kj47qfrvtep2coylu");
        uris[0].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreicwlut5fat6egxcweyeak2uognc43lm7mtjgxtdiguw2gcwxvw33i");
        uris[0].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreiabd2hyz5yknzs5h6hg7l7xcfhhzdd6umrrcdcf6yolyeloytsdry");
        uris[0].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreifmmvtiuxfq4wpqdr5lgptwr4lxj2rcztntw74kqc2ildfovcv2ny");
        uris[0].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreih6ik3awoqmbga3qfmyaurfhfoxcvw6imet352irz4h7qybslmi3q");
        
        uris[1].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreidjvljmufi2qbteidziz23ea7xlxey5ggxl2w2wk4ck3ojyb4y7oi");
        uris[1].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreicldumkg2ytahxb6lpyksk6q5nsrp2g7sk7bzzwautweqtqpnnr5e");
        uris[1].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreie3ppzd3zyzlszg6ivhdhghcc7heynjnrhkrl2sng7lwu4lmybeui");
        uris[1].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreif5nggmkgibbe3hn47l7lzkkbaid7rump2s7pyi5fazzfhx4ajkj4");
        
        uris[2].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreie3fkgdsqfjjsifqpgwmxnafcgnb3onv4hy6pyrthwge37fqmerei");
        uris[2].push("https://jade-electrical-earwig-826.mypinata.cloud/ipfs/bafkreihdqwydegzuw3tilmbx4iflvacsd54efjvq2v3mbyyqct5gnuyocy");
    }

    modifier onlyMysteryBox() {
        require(msg.sender == mysteryBoxContract, "Not authorized");
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, CCIPReceiver) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || CCIPReceiver.supportsInterface(interfaceId);
    }

    // +-------------------------------------+
    // | BRIDGE FUNCTIONS - Sepolia and Fuji |
    // +-------------------------------------+
    function bridgeToSepolia(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(sepoliaMirror != address(0), "Sepolia mirror not set");
        
        uint256 playerType = tokenIdToType[tokenId];
        uint256 uriIndex = tokenIdToUriIndex[tokenId];
        
        // Update playerNftFrq (remove specific tokenId from current owner)
        _removeTokenFromArray(msg.sender, playerType, uriIndex, tokenId);
        
        _burn(tokenId);
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(sepoliaMirror),
            data: abi.encode(msg.sender, tokenId, playerType, uriIndex),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000})),
            feeToken: address(0)
        });

        uint256 fees = s_router.getFee(SEPOLIA_CHAIN_SELECTOR, message);
        require(msg.value >= fees, "Insufficient fee");
        
        bytes32 messageId = s_router.ccipSend{value: fees}(SEPOLIA_CHAIN_SELECTOR, message);
        
        if (msg.value > fees) {
            payable(msg.sender).transfer(msg.value - fees);
        }
        
        emit NFTBridged(msg.sender, tokenId, SEPOLIA_CHAIN_SELECTOR, messageId);
    }

    function bridgeToFuji(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(fujiMirror != address(0), "Fuji mirror not set");
        
        uint256 playerType = tokenIdToType[tokenId];
        uint256 uriIndex = tokenIdToUriIndex[tokenId];
        
        _removeTokenFromArray(msg.sender, playerType, uriIndex, tokenId);
        
        _burn(tokenId);
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(fujiMirror),
            data: abi.encode(msg.sender, tokenId, playerType, uriIndex),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000})),
            feeToken: address(0)
        });

        uint256 fees = s_router.getFee(FUJI_CHAIN_SELECTOR, message);
        require(msg.value >= fees, "Insufficient fee");
        
        bytes32 messageId = s_router.ccipSend{value: fees}(FUJI_CHAIN_SELECTOR, message);
        
        if (msg.value > fees) {
            payable(msg.sender).transfer(msg.value - fees);
        }
        
        emit NFTBridged(msg.sender, tokenId, FUJI_CHAIN_SELECTOR, messageId);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        uint64 sourceChain = message.sourceChainSelector;
        address mirrorContract = abi.decode(message.sender, (address));
        
        if (sourceChain == SEPOLIA_CHAIN_SELECTOR) {
            require(mirrorContract == sepoliaMirror, "Invalid sender");
        } else if (sourceChain == FUJI_CHAIN_SELECTOR) {
            require(mirrorContract == fujiMirror, "Invalid sender");
        } else {
            revert("Chain not supported");
        }
        
        (address owner, , uint256 playerType, uint256 uriIndex) = abi.decode(message.data, (address, uint256, uint256, uint256));
        
        uint256 newTokenId = _tokenIdCounter.current();
        _safeMint(owner, newTokenId);
        
        tokenIdToUriIndex[newTokenId] = uriIndex;
        tokenIdToType[newTokenId] = playerType;
        playerNftFrq[owner][playerType][uriIndex].push(newTokenId);
        
        _tokenIdCounter.increment();
        
        emit PlayerMinted(owner, playerType, uriIndex);
        emit TokenOwnershipChanged(address(0), owner, newTokenId, uriIndex);
        emit NFTReceived(owner, newTokenId, sourceChain, message.messageId);
    }

    // +------------------+
    // | setter functions |
    // +------------------+
    function setSepoliaMirror(address _sepoliaMirror) external onlyOwner {
        sepoliaMirror = _sepoliaMirror;
    }

    function setFujiMirror(address _fujiMirror) external onlyOwner {
        fujiMirror = _fujiMirror;
    }

    function setMysteryBoxContract(address _mysteryBoxContract) external onlyOwner {
        mysteryBoxContract = _mysteryBoxContract;
    }

    function addNewPlayer(uint playerType, string memory uri) external onlyOwner {
        uris[playerType].push(uri);
        emit NewPlayerAdded(playerType,uris[playerType].length - 1, uri);
    }

    // +----------------+
    // | Game functions |
    // +----------------+
    function mintPlayer(address to, uint playerType, uint256 uriIndex) external onlyMysteryBox {
        require(uriIndex < uris[playerType].length, "Invalid URI index");

        uint tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        
        tokenIdToUriIndex[tokenId] = uriIndex;
        tokenIdToType[tokenId] = playerType;

        _tokenIdCounter.increment();
        playerNftFrq[to][playerType][uriIndex].push(tokenId);
        
        emit PlayerMinted(to, tokenId, uriIndex);
        emit TokenOwnershipChanged(address(0), to, tokenId, uriIndex);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0) && to != address(0)) {
            uint256 uriIndex = tokenIdToUriIndex[tokenId];
            uint256 playerType = tokenIdToType[tokenId];
            _removeTokenFromArray(from, playerType, uriIndex, tokenId);
            playerNftFrq[to][playerType][uriIndex].push(tokenId);
            emit TokenOwnershipChanged(from, to, tokenIdToType[tokenId], uriIndex);
        }
    }

    // +------------------+
    // | getter functions |
    // +------------------+
    function tokenURI(uint tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return uris[tokenIdToType[tokenId]][tokenIdToUriIndex[tokenId]];
    }

    function totalURIs(uint playerType) external view returns (uint256) {
        return uris[playerType].length;
    }

    function getTokenCount(address owner) external view returns (uint[][] memory) {
        uint[][] memory counts = new uint[][](3);
        
        for (uint playerType = 0; playerType < 3; playerType++) {
            counts[playerType] = new uint[](uris[playerType].length);
            for (uint uriIndex = 0; uriIndex < uris[playerType].length; uriIndex++) {
                counts[playerType][uriIndex] = playerNftFrq[owner][playerType][uriIndex].length;
            }
        }
        
        return counts;
    }
    
    function getLastTokenOf(address owner, uint playerType, uint uriIndex) external view returns (uint) {
        uint[] memory tokens = playerNftFrq[owner][playerType][uriIndex];
        require(tokens.length > 0, "No tokens for this player");
        return tokens[tokens.length - 1];
    }

    function getPlayerTokens(address owner, uint playerType, uint uriIndex) external view returns (uint[] memory) {
        return playerNftFrq[owner][playerType][uriIndex];
    }

    function getPlayerTokensLength(address owner, uint playerType, uint uriIndex) external view returns (uint) {
        return playerNftFrq[owner][playerType][uriIndex].length;
    }
 
    // +------------------+
    // | hellper function |
    // +------------------+
    function _removeTokenFromArray(address owner, uint256 playerType, uint256 uriIndex, uint256 tokenId) internal {
        uint[] storage tokens = playerNftFrq[owner][playerType][uriIndex];
        
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                // Move last element to current position and remove last element
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }

    receive() external payable {}
} 