//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

// needed for upgradability
//import "@openzeppelin/upgrades/contracts/Initializable.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./TinyBoxesRenderer.sol";

// Chainlink Contracts
import "./chainlink/ChainlinkClient.sol";
import "./chainlink/VRFConsumerBase.sol";
import "./chainlink/interfaces/AggregatorInterface.sol";

contract TinyBoxes is
    ERC721,
    VRFConsumerBase,
    ChainlinkClient,
    TinyBoxesRenderer
{
    using SafeMath_TinyBoxes for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;
    AggregatorInterface internal refFeed;
    LinkTokenInterface internal LINK_TOKEN;

    uint256 public linkPremium = 2000; // in percent * 1000
    uint256 public startPrice = 160000000000000000; // in wei
    uint256 public priceIncrease = 1000000000000000; // in wei

    uint256 public constant TOKEN_LIMIT = 1024;
    uint256 public constant ARTIST_PRINTS = 0;
    uint256 public constant ANIMATION_COUNT = 5;
    address public animator;
    address public deployer;
    address payable artmuseum = 0x027Fb48bC4e3999DCF88690aEbEBCC3D1748A0Eb; //lolz

    // Chainlink VRF and Feed Stuff
    address constant DEFAULT_FEED_ADDRESS = 0xb8c99b98913bE2ca4899CdcaF33a3e519C20EeEc; // Ropsten
    address constant VRF_COORDINATOR = 0xf720CF1B963e0e7bE9F58fd471EFa67e7bF00cfb; // Ropsten
    bytes32 constant KEY_HASH = 0xced103054e349b8dfb51352f0f8fa9b5d20dde3d06f9f43cb2b85bc64b238205; // Ropsten
    // address constant VRF_COORDINATOR = 0xc1031337fe8E75Cf25CAe9828F3BF734d83732e4; // Rinkeby
    //bytes32 constant KEY_HASH = 0xcad496b9d0416369213648a32b4975fff8707f05dfb43603961b58f3ac6617a7; // Rinkeby
    uint256 constant fee = 10**18;

    struct Request {
        address creator;
        uint256 id;
    }

    mapping(uint256 => TinyBox) internal boxes;
    mapping(bytes32 => Request) internal requests;
    mapping(address => bool) internal mayWithdraw;

    /**
     * @dev Contract constructor.
     * @notice Constructor inherits VRFConsumerBase
     */
    constructor(
        address _animator,
        address _link,
        address _feed
    )
        public
        ERC721("TinyBoxes", "[#][#]")
        VRFConsumerBase(VRF_COORDINATOR, chainlinkTokenAddress())
    {
        deployer = msg.sender;
        animator = _animator;

        // Set the address for the LINK token to the public network address
        // or use an address provided as a parameter if set
        if (_link == address(0)) setPublicChainlinkToken();
        else setChainlinkToken(_link);
        // Init LINK token interface
        LINK_TOKEN = LinkTokenInterface(chainlinkTokenAddress());
        // set the feed address and init the interface
        if (_feed == address(0))
            refFeed = AggregatorInterface(DEFAULT_FEED_ADDRESS); // init LINK/ETH with default aggrigator contract address
        else refFeed = AggregatorInterface(_feed); // init LINK/ETH with custom aggrigator contract address
    }

    /**
     * @notice Modifier to only allow randomness fulfillment by the VRFCoordinator contract
     */
    modifier onlyVRFCoordinator {
        require(
            msg.sender == VRF_COORDINATOR,
            "Fulfillment only allowed by VRFCoordinator"
        );
        _;
    }

    /**
     * @notice Modifier to only allow URI updates by the Animator address
     */
    modifier onlyAnimator {
        require(msg.sender == animator, "URI update only allowed by Animator");
        _;
    }

    /**
     * @notice Modifier to only allow contract deployer to call a function
     */
    modifier onlyDeployer {
        require(
            msg.sender == deployer,
            "Only the contract deployer may call this function"
        );
        _;
    }

    /**
     * @notice Modifier to only calls from the LINK token address
     */
    modifier onlyLINK {
        require(
            msg.sender == chainlinkTokenAddress(),
            "URI update only allowed by Animator"
        );
        _;
    }

    /**
     * @notice Modifier to check if tokens are sold out
     */
    modifier notSoldOut {
        // ensure we still have not reached the cap
        require(
            _tokenIds.current() < TOKEN_LIMIT,
            "ART SALE IS OVER. Tinyboxes are now only available on the secondary market."
        );
        _;
    }

    /**
     * @dev Withdraw LINK tokens from the contract balance to contract owner
     * @param amount of link to withdraw (in smallest divisions of 10**18)
     */
    // TODO: make a version that checks to see we have enough link to fullfill randomness for remaining unminted tokens
    function withdrawLINK(uint256 amount) external returns (bool) {
        // ensure the address is approved for withdraws
        require(
            msg.sender == deployer || mayWithdraw[msg.sender],
            "Only the contract owner may withdraw LINK"
        );
        // ensure we have at least that much LINK
        require(
            LINK_TOKEN.balanceOf(address(this)) >= amount,
            "Not enough LINK for requested withdraw"
        );
        // send amount of LINK tokens to the transaction sender
        return LINK_TOKEN.transfer(msg.sender, amount);
    }

    /**
     * @dev Approve an address for LINK withdraws
     * @param account address to approve
     */
    function aproveForWithdraw(address account) external onlyDeployer {
        // set account address to true in witdraw aproval mapping
        mayWithdraw[account] = true;
    }

    /**
     * @dev Accept incoming LINK ERC20+677 tokens, unpack bytes data and run create with results
     * @param from address of token sender
     * @param amount of tokens transfered
     * @param data of token to create
     * @return success (token recieved) boolean value
     */
    function onTokenTransfer(
        address from,
        uint256 amount,
        bytes calldata data
    ) external onlyLINK notSoldOut returns (bool) {
        // TODO: unpack parameters from bytes data
        // if still minting the beta sale
        if (_tokenIds.current() < ARTIST_PRINTS) {
            // check the address is authorized
            require(
                msg.sender == deployer,
                "Only the creator can mint the alpha token. Wait your turn FFS"
            );
        } else {
            // make sure all later calls pay enough and get change
            uint256 price = currentLinkPrice();
            require(amount >= price, "insuficient payment"); // return if they dont pay enough
            if (amount > price) LINK_TOKEN.transfer(from, amount - price); // give change if they over pay
        }

        // create variables to unpack data into
        uint256 seed = 0;
        uint8[2] memory counts = [1, 1];
        int16[13] memory dials = [
            int16(100),
            int16(100),
            int16(3),
            int16(3),
            int16(100),
            int16(200),
            int16(100),
            int16(200),
            int16(3),
            int16(750),
            int16(1200),
            int16(2400),
            int16(100)
        ];
        bool[3] memory mirrors = [true, true, true];

        // create a new box object
        TinyBox memory box = TinyBox({
            seed: seed,
            randomness: 0,
            animation: 0,
            shapes: counts[1],
            colors: counts[0],
            spacing: [
                uint16(dials[0]),
                uint16(dials[1]),
                uint16(dials[2]),
                uint16(dials[3])
            ],
            size: [
                uint16(dials[4]),
                uint16(dials[5]),
                uint16(dials[6]),
                uint16(dials[7])
            ],
            hatching: uint16(dials[8]),
            mirrorPositions: [dials[9], dials[10], dials[11]],
            scale: uint16(dials[12]),
            mirrors: mirrors
        });

        // register the new box
        createBox(box);

        return true;
    }

    /**
     * @dev Create a new TinyBox Token
     * @param _seed of token
     * @param counts of token colors & shapes
     * @param dials of token renderer
     * @param mirrors active boolean of token
     * @return _requestId of the VRF call
     */
    function buy(
        string calldata _seed,
        uint8[2] calldata counts,
        int16[13] calldata dials,
        bool[3] calldata mirrors
    ) external payable notSoldOut returns (bytes32) {
        // if still minting the beta sale
        if (_tokenIds.current() < ARTIST_PRINTS) {
            // check the address is authorized
            require(
                msg.sender == deployer,
                "Only the creator can mint the alpha token. Wait your turn FFS"
            );
        } else {
            // make sure all later calls pay enough and get change
            uint256 amount = currentPrice();
            require(msg.value >= amount, "insuficient payment"); // return if they dont pay enough
            if (msg.value > amount) msg.sender.transfer(msg.value - amount); // give change if they over pay
            artmuseum.transfer(amount); // send the payment amount to the artmuseum account
        }

        // convert user seed from string to uint
        uint256 seed = Random.stringToUint(_seed);

        // create a new box object
        TinyBox memory box = TinyBox({
            seed: seed,
            randomness: 0,
            animation: 0,
            shapes: counts[1],
            colors: counts[0],
            spacing: [
                uint16(dials[0]),
                uint16(dials[1]),
                uint16(dials[2]),
                uint16(dials[3])
            ],
            size: [
                uint16(dials[4]),
                uint16(dials[5]),
                uint16(dials[6]),
                uint16(dials[7])
            ],
            hatching: uint16(dials[8]),
            mirrorPositions: [dials[9], dials[10], dials[11]],
            scale: uint16(dials[12]),
            mirrors: mirrors
        });

        // register the new box
        return createBox(box);
    }

    /**
     * @dev Create a new TinyBox Token
     * @param box object of token data
     * @return _requestId of the VRF call
     */
    function createBox(TinyBox memory box) internal returns (bytes32) {
        // make sure caller is never the 0 address
        require(
            msg.sender != address(0),
            "token recipient man not be the zero address"
        );
        // ensure we have enough LINK token in the contract to pay for VRF
        require(
            LINK_TOKEN.balanceOf(address(this)) > fee,
            "Not enough LINK for a VRF request"
        );

        // register the new box data
        boxes[_tokenIds.current()] = box;

        // Hash user seed and blockhash for VRFSeed
        uint256 seedVRF = uint256(
            keccak256(abi.encode(box.seed, blockhash(block.number)))
        );

        // send VRF request
        bytes32 _requestId = requestRandomness(KEY_HASH, fee, seedVRF);

        // map VRF requestId to next token id and owner
        requests[_requestId] = Request(msg.sender, _tokenIds.current());

        // increment the id counter for the next call
        _tokenIds.increment();

        return _requestId;
    }

    /**
     * @notice Callback function used by VRF Coordinator
     * @dev Important! Add a modifier to only allow this function to be called by the VRFCoordinator
     * @dev This is where you do something with randomness!
     * @dev The VRF Coordinator will only send this function verified responses.
     * @dev The VRF Coordinator will not pass randomness that could not be verified.
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        external
        override
        onlyVRFCoordinator
    {
        // lookup saved data from the requestId
        Request memory req = requests[requestId];

        // store the randomness in the token data
        boxes[req.id].randomness = randomness;

        // --- Use The Provided Randomness ---

        // initilized RNG with the provided varifiable randomness and blocks 0 through 1
        bytes32[] memory pool = Random.init(0, 1, randomness);

        // TODO - generate animation with RNG weighted non uniformly for varying rarity types
        // maybe use log base 2 of a number in a range 2 to the animation counts
        uint8 animation = uint8(
            Random.uniform(pool, 0, int256(ANIMATION_COUNT) - 1)
        );

        // --- Save data to storage ---

        // update box data relying on randomness
        boxes[req.id].animation = animation;

        // mint the token to the creator
        _safeMint(req.creator, req.id);
    }

    /**
     * @dev Update the token URI field
     * @dev Only the animator role can call this
     */
    function updateURI(uint256 _id, string calldata _uri)
        external
        onlyAnimator
    {
        _setTokenURI(_id, _uri);
    }

    /**
     * @dev Get the current price of a token in LINK (Chainlink Token)
     * @return price in LINK of a token currently
     */
    function currentLinkPrice() public view returns (uint256 price) {
        price = linkPriceAt(_tokenIds.current());
    }

    /**
     * @dev Get the price of token number _id in LINK (Chainlink Token)
     * @return price in LINK of a token currently
     */
    function linkPriceAt(uint256 _id) public view returns (uint256 price) {
        price = ethToLink(priceAt(_id));
    }

    /**
     * @dev Convert a price in Eth to one in LINK (Chainlink Token)
     * @return price in LINK eqivalent to the provided Eth price
     */
    function ethToLink(uint256 priceEth) internal view returns (uint256 price) {
        price = ((((priceEth * 10**18) / uint256(refFeed.latestAnswer())) *
            ((10**5 + linkPremium))) / 10**5);
    }

    /**
     * @dev Get the current price of a token
     * @return price in wei of a token currently
     */
    function currentPrice() public view returns (uint256 price) {
        price = priceAt(_tokenIds.current());
    }

    /**
     * @dev Get the price of a specific token id
     * @param _id of the token
     * @return price in wei of token id
     */
    function priceAt(uint256 _id) public view returns (uint256 price) {
        uint256 tokeninflation = (_id / 2) * priceIncrease; // add .001 eth to price per 2 tokens minted
        price = startPrice + tokeninflation;
    }

    /**
     * @dev Lookup the seed
     * @param _id for which we want the seed
     * @return seed value of _id.
     */
    function tokenSeed(uint256 _id) external view returns (uint256) {
        return boxes[_id].seed;
    }

    /**
     * @dev Lookup the animation
     * @param _id for which we want the animation
     * @return animation value of _id.
     */
    function tokenAnimation(uint256 _id) external view returns (uint256) {
        return boxes[_id].animation;
    }

    /**
     * @dev Lookup all token data in one call
     * @param _id for which we want token data
     * @return seed of token
     * @return randomness provided by Chainlink VRF
     * @return animation of token
     * @return colors of token
     * @return shapes of token
     * @return hatching of token
     * @return size of token
     * @return spacing of token
     * @return mirrorPositions of token
     * @return mirrors of token
     * @return scale of token
     */
    function tokenData(uint256 _id)
        external
        view
        returns (
            uint256 seed,
            uint256 randomness,
            uint8 animation,
            uint8 colors,
            uint8 shapes,
            uint16 hatching,
            uint16[4] memory size,
            uint16[4] memory spacing,
            int16[3] memory mirrorPositions,
            bool[3] memory mirrors,
            uint16 scale
        )
    {
        TinyBox memory box = boxes[_id];
        seed = box.seed;
        randomness = box.randomness;
        animation = box.animation;
        colors = box.colors;
        shapes = box.shapes;
        hatching = box.hatching;
        size = box.size;
        spacing = box.spacing;
        mirrorPositions = box.mirrorPositions;
        mirrors = box.mirrors;
        scale = box.scale;
    }

    /**
     * @dev Generate the token SVG art preview for given parameters
     * @param _seed for renderer RNG
     * @param counts for colors and shapes
     * @param dials for perpetual renderer
     * @param mirrors switches
     * @return preview SVG art
     */
    function tokenPreview(
        uint256 _id,
        string memory _seed,
        uint8[2] memory counts,
        int16[13] memory dials,
        bool[3] memory mirrors
    ) public view returns (string memory) {
        TinyBox memory box = TinyBox({
            seed: Random.stringToUint(_seed),
            randomness: Random.stringToUint(_seed),
            animation: 0,
            shapes: counts[1],
            colors: counts[0],
            spacing: [
                uint16(dials[0]),
                uint16(dials[1]),
                uint16(dials[2]),
                uint16(dials[3])
            ],
            size: [
                uint16(dials[4]),
                uint16(dials[5]),
                uint16(dials[6]),
                uint16(dials[7])
            ],
            hatching: uint16(dials[8]),
            mirrorPositions: [dials[9], dials[10], dials[11]],
            scale: uint16(dials[12]),
            mirrors: mirrors
        });
        return Buffer.toString(perpetualRenderer(box, 0));
    }

    /**
     * @dev Generate the token SVG art of a specified frame
     * @param _id for which we want art
     * @param _frame for which we want art
     * @return animated SVG art of token _id at _frame.
     */
    function tokenFrame(uint256 _id, uint256 _frame)
        public
        view
        returns (string memory)
    {
        TinyBox memory box = boxes[_id];
        return Buffer.toString(perpetualRenderer(box, _frame));
    }

    /**
     * @dev Generate the static token SVG art
     * @param _id for which we want art
     * @return URI of _id.
     */
    function tokenArt(uint256 _id) external view returns (string memory) {
        // render frame 0 of the token animation
        return tokenFrame(_id, 0);
    }
}
