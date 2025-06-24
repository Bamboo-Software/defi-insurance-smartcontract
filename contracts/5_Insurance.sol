// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";

/**
 * @title AgriculturalInsurance
 * @dev Smart contract for agricultural insurance on Avalanche network
 */
contract AgriculturalInsurance is Ownable, ReentrancyGuard, Pausable, ChainlinkClient {
    
    // Master wallet to receive payments
    address public masterWallet;
    
    // Compact location struct
    struct CompactLocation {
        int32 lat;
        int32 lon;
    }

    CompactLocation[] public locations;
    mapping(bytes32 => bool) public isActive;

    event InsurancePurchased(
        address indexed policyholder,
        int32 lat,
        int32 lon,
        uint256 startDate,
        uint256 premiumAmount,
        string paymentToken,
        uint256 timestamp
    );
    
    // Mapping to store allowed ERC20 tokens
    mapping(address => bool) public allowedERC20Tokens;

    // Chainlink oracle config
    using Chainlink for Chainlink.Request;
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    address private linkToken;

    // Weather data storage
    mapping(bytes32 => int256) public latestWeatherData; // requestId => weather value

    event WeatherDataRequested(bytes32 indexed requestId, int32 lat, int32 lon);
    event WeatherDataReceived(bytes32 indexed requestId, int256 weatherValue);
    
    // Modifiers
    modifier allowedToken(address tokenAddress) {
        require(allowedERC20Tokens[tokenAddress], "ERC20 token not allowed");
        _;
    }
    
    /**
     * @dev Constructor sets the deployer as owner and master wallet
     */
    constructor() Ownable(msg.sender) {
        masterWallet = msg.sender;
        
        // Allow USDC by default
        allowedERC20Tokens[0x5425890298aed601595a70AB815c96711a31Bc65] = true;
    }
    
    /**
     * @dev Purchase insurance with native token (AVAX)
     * @param lat Latitude coordinate (int32)
     * @param lon Longitude coordinate (int32)
     * @param startDate Start date of insurance coverage
     * @param premiumAmount Amount of AVAX to pay
     */
    function purchaseInsuranceWithNative(
        int32 lat,
        int32 lon,
        uint256 startDate,
        uint256 premiumAmount
    ) external payable nonReentrant whenNotPaused {
        require(premiumAmount > 0, "Premium must be greater than 0");
        require(msg.value == premiumAmount, "Incorrect premium amount sent");
        require(startDate > block.timestamp, "Start date must be in the future");
        (bool success, ) = payable(masterWallet).call{value: msg.value}("");
        require(success, "Failed to transfer AVAX to master wallet");
        addLocation(lat, lon);
        emit InsurancePurchased(
            msg.sender,
            lat,
            lon,
            startDate,
            premiumAmount,
            "AVAX",
            block.timestamp
        );
    }
    
    /**
     * @dev Purchase insurance with ERC20 token
     * @param tokenAddress ERC20 token address
     * @param lat Latitude coordinate (int32)
     * @param lon Longitude coordinate (int32)
     * @param startDate Start date of insurance coverage
     * @param premiumAmount Amount of ERC20 token to pay
     */
    function purchaseInsuranceWithERC20(
        address tokenAddress,
        int32 lat,
        int32 lon,
        uint256 startDate,
        uint256 premiumAmount
    ) external nonReentrant whenNotPaused allowedToken(tokenAddress) {
        require(startDate > block.timestamp, "Start date must be in the future");
        require(premiumAmount > 0, "Premium must be greater than 0");
        IERC20 token = IERC20(tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= premiumAmount, "Insufficient allowance");
        require(
            token.transferFrom(msg.sender, masterWallet, premiumAmount),
            "ERC20 transfer failed"
        );
        addLocation(lat, lon);
        emit InsurancePurchased(
            msg.sender,
            lat,
            lon,
            startDate,
            premiumAmount,
            "ERC20",
            block.timestamp
        );
    }
    
    /**
     * @dev Allow or disallow ERC20 token (owner only)
     */
    function setERC20TokenAllowed(address tokenAddress, bool allowed) external onlyOwner {
        allowedERC20Tokens[tokenAddress] = allowed;
    }
    
    /**
     * @dev Check if ERC20 token is allowed
     */
    function isTokenAllowed(address tokenAddress) external view returns (bool) {
        return allowedERC20Tokens[tokenAddress];
    }
    
    /**
     * @dev Change master wallet (owner only)
     */
    function changeMasterWallet(address newMasterWallet) external onlyOwner {
        require(newMasterWallet != address(0), "Invalid master wallet address");
        masterWallet = newMasterWallet;
    }
    
    /**
     * @dev Add location and mark as active
     */
    function addLocation(int32 lat, int32 lon) public {
        locations.push(CompactLocation(lat, lon));
        bytes32 key = keccak256(abi.encode(lat, lon));
        isActive[key] = true;
    }
    
    /**
     * @dev Pause contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Emergency withdraw AVAX (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No AVAX to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Failed to withdraw AVAX");
    }
    
    /**
     * @dev Emergency withdraw ERC20 token (owner only)
     */
    function emergencyWithdrawERC20(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        require(token.transfer(owner(), balance), "Failed to withdraw tokens");
    }
    
    /**
     * @dev Set Chainlink oracle config (owner only)
     */
    function setChainlinkOracle(
        address _oracle,
        bytes32 _jobId,
        uint256 _fee,
        address _linkToken
    ) external onlyOwner {
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
        linkToken = _linkToken;
        _setChainlinkToken(_linkToken);
    }

    /**
     * @dev Owner requests weather data for a location
     */
    function requestWeatherData(int32 lat, int32 lon) external onlyOwner returns (bytes32 requestId) {
        require(oracle != address(0), "Oracle not set");
        Chainlink.Request memory req = _buildChainlinkRequest(jobId, address(this), this.fulfillWeatherData.selector);
        // Example: encode lat/lon as string, adapt to your oracle's API
        req._add("lat", intToString(lat));
        req._add("lon", intToString(lon));
        requestId = _sendChainlinkRequestTo(oracle, req, fee);
        emit WeatherDataRequested(requestId, lat, lon);
    }

    /**
     * @dev Chainlink node calls this to fulfill weather data
     */
    function fulfillWeatherData(bytes32 _requestId, int256 _weatherValue) public recordChainlinkFulfillment(_requestId) {
        latestWeatherData[_requestId] = _weatherValue;
        emit WeatherDataReceived(_requestId, _weatherValue);
    }

    // Helper: int32 to string
    function intToString(int32 value) internal pure returns (string memory) {
        if (value >= 0) {
            return _toString(uint32(value));
        } else {
            return string(abi.encodePacked("-", _toString(uint32(-value))));
        }
    }
    function _toString(uint32 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint32 temp = value;
        uint32 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint32(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    // Receive function to accept AVAX
    receive() external payable {
        revert("Use purchaseInsuranceWithNative function");
    }
}
