// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";

using Chainlink for Chainlink.Request;

/**
 * @title AgriculturalInsurance
 * @dev Smart contract for agricultural insurance on Avalanche network
 */
contract AgriculturalInsurance is Ownable, ReentrancyGuard, Pausable, ChainlinkClient {
    
    // Master wallet to receive payments
    address public masterWallet;
    
    // Chainlink oracle config
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    address private linkToken;

    // Compact location struct
    struct CompactLocation {
        int32 lat;
        int32 lon;
    }

    // Location storage
    mapping(bytes32 => CompactLocation) public locations;
    mapping(bytes32 => bool) public isActive;

    // Mapping to store allowed ERC20 tokens
    mapping(address => bool) public allowedERC20Tokens;

    // Weather data storage
    mapping(bytes32 => mapping(bytes32 => int256)) public weatherDataByLocation;

    // Log type
    enum LogType { INFO, ERROR }

    event InsurancePurchased(
        address indexed user,
        string packageId,
        address tokenAddress,
        uint256 premiumAmount,
        int32 lat,
        int32 lon,
        uint256 startDate,
        string tokenType,
        uint256 timestamp
    );
    event WeatherDataRequested(bytes32 indexed requestId, int32 lat, int32 lon);
    event WeatherDataReceived(bytes32 indexed requestId, int256 weatherValue);
    event EmergencyWithdraw(address indexed owner, uint256 amount, string tokenType);
    event Log(LogType logType, string message);

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
        _setChainlinkToken(0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846); // LINK Fuji
    }
    
    /**
     * @dev Purchase insurance with native token (AVAX)
     * @param packageId Package ID
     * @param lat Latitude coordinate (int32)
     * @param lon Longitude coordinate (int32)
     * @param startDate Start date of insurance coverage
     * @param premiumAmount Amount of AVAX to pay
     */
    function purchaseInsuranceWithNative(
        string memory packageId,
        int32 lat,
        int32 lon,
        uint256 startDate,
        uint256 premiumAmount
    ) external payable nonReentrant whenNotPaused {
        require(premiumAmount > 0, "Premium must be greater than 0");
        require(msg.value == premiumAmount, "Incorrect amount sent");
        require(startDate > block.timestamp, "Start date must be in future");
        (bool sent, ) = masterWallet.call{value: msg.value}("");
        require(sent, "Failed to send AVAX");
        addLocation(lat, lon);
        emit InsurancePurchased(
            msg.sender,
            packageId,
            address(0),
            premiumAmount,
            lat,
            lon,
            startDate,
            "AVAX",
            block.timestamp
        );
    }
    
    /**
     * @dev Purchase insurance with ERC20 token
     * @param packageId Package ID
     * @param lat Latitude coordinate (int32)
     * @param lon Longitude coordinate (int32)
     * @param startDate Start date of insurance coverage
     * @param premiumAmount Amount of ERC20 token to pay
     * @param tokenAddress ERC20 token address
     */
    function purchaseInsuranceWithERC20(
        string memory packageId,
        int32 lat,
        int32 lon,
        uint256 startDate,
        uint256 premiumAmount,
        address tokenAddress
    ) external nonReentrant whenNotPaused allowedToken(tokenAddress) {
        require(startDate > block.timestamp, "Start date must be in future");
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
            packageId,
            tokenAddress,
            premiumAmount,
            lat,
            lon,
            startDate,
            "ERC20",
            block.timestamp
        );
    }
    
    /**
     * @dev Allow or disallow ERC20 token (owner only)
     */
    function setTokenAllowed(address tokenAddress, bool allowed) external onlyOwner {
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
        require(newMasterWallet != address(0), "Invalid address");
        masterWallet = newMasterWallet;
    }
    
    /**
     * @dev Add location and mark as active
     * @param lat Latitude coordinate (int32)
     * @param lon Longitude coordinate (int32)
     */
    function addLocation(int32 lat, int32 lon) internal {
        bytes32 key = keccak256(abi.encode(lat, lon));
        if (lat < -90000000 || lat > 90000000) {
            emit Log(LogType.ERROR, string(abi.encodePacked("Invalid latitude: ", intToStringWithDecimal(lat))));
            revert("Invalid latitude");
        }
        if (lon < -180000000 || lon > 180000000) {
            emit Log(LogType.ERROR, string(abi.encodePacked("Invalid longitude: ", intToStringWithDecimal(lon))));
            revert("Invalid longitude");
        }
        if (!isActive[key]) {
            locations[key] = CompactLocation(lat, lon);
            isActive[key] = true;
        }
    }

    /**
     * @dev Deactivate location (owner only)
     * @param lat Latitude coordinate (int32)
     * @param lon Longitude coordinate (int32)
     */
    function deactivateLocation(int32 lat, int32 lon) external onlyOwner {
        bytes32 key = keccak256(abi.encode(lat, lon));
        require(isActive[key], "Location not active");
        isActive[key] = false;
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
    function emergencyWithdrawAVAX(uint256 amount) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance >= amount && amount > 0, "Invalid withdraw amount");
        (bool sent, ) = owner().call{value: amount}("");
        require(sent, "Failed to withdraw AVAX");
        emit EmergencyWithdraw(owner(), amount, "AVAX");
    }
    
    /**
     * @dev Emergency withdraw ERC20 token (owner only)
     */
    function emergencyWithdrawERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount && amount > 0, "Invalid withdraw amount");
        require(token.transfer(owner(), amount), "Failed to withdraw tokens");
        emit EmergencyWithdraw(owner(), amount, "ERC20");
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
        emit Log(LogType.INFO, string(abi.encodePacked("Chainlink oracle set: ", _oracle, " ", _jobId, " ", _fee, " ", _linkToken)));
    }

    /**
     * @dev Owner requests weather data for a location
     */
    function requestWeatherData(int32 lat, int32 lon) external onlyOwner returns (bytes32 requestId) {
        bytes32 key = keccak256(abi.encode(lat, lon));
        emit Log(LogType.INFO, string(abi.encodePacked("Key: ", key)));

        require(isActive[key], "Location not registered");
        
        if (oracle == address(0)) {
            emit Log(LogType.ERROR, "Invalid oracle address");
            revert("Oracle not set");
        }
        if (linkToken == address(0)) {
            emit Log(LogType.ERROR, "Link token not set");
            revert("Link token not set");
        }
        IERC20 link = IERC20(linkToken);
        if (link.balanceOf(address(this)) < fee) {
            emit Log(LogType.ERROR, "Insufficient LINK balance");
            revert("Insufficient LINK balance");
        }

        emit Log(LogType.INFO, string(abi.encodePacked("Oracle: ", oracle)));

        Chainlink.Request memory request = _buildChainlinkRequest(jobId, address(this), this.fulfillWeatherData.selector);
        request._add("lat", intToStringWithDecimal(lat));
        request._add("lon", intToStringWithDecimal(lon));

        // Send Chainlink request
        requestId = _sendChainlinkRequestTo(oracle, request, fee);
        emit WeatherDataRequested(requestId, lat, lon);
    }

    /**
     * @dev Chainlink node calls this to fulfill weather data
     */
    function fulfillWeatherData(bytes32 requestId, int256 weatherValue, int32 lat, int32 lon) 
        public recordChainlinkFulfillment(requestId) {
        bytes32 locationKey = keccak256(abi.encode(lat, lon));
        weatherDataByLocation[locationKey][requestId] = weatherValue;
        emit WeatherDataReceived(requestId, weatherValue);
    }

    function intToStringWithDecimal(int32 _value) internal pure returns (string memory) {
        if (_value == 0) return "0.000000";
        bool negative = _value < 0;
        uint32 absValue = uint32(negative ? -_value : _value);
        uint32 integerPart = absValue / 1_000_000;
        uint32 decimalPart = absValue % 1_000_000;
        string memory intStr = _toString(integerPart);
        string memory decStr = _toString(decimalPart);
        // Pad decimals to 6 digits
        while (bytes(decStr).length < 6) {
            decStr = string(abi.encodePacked("0", decStr));
        }
        return negative
            ? string(abi.encodePacked("-", intStr, ".", decStr))
            : string(abi.encodePacked(intStr, ".", decStr));
    }

    function _toString(uint32 _value) internal pure returns (string memory) {
        if (_value == 0) return "0";
        uint32 temp = _value;
        uint32 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint32(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }

    function getLinkBalance() external view onlyOwner returns (uint256) {
        return IERC20(linkToken).balanceOf(address(this));
    }

    function depositLink(uint256 _amount) external {
        IERC20(linkToken).transferFrom(msg.sender, address(this), _amount);
    }

    function withdrawLink(uint256 _amount) external onlyOwner {
        IERC20(linkToken).transfer(owner(), _amount);
    }
    
    // Receive function to accept AVAX
    receive() external payable {
        revert("Use purchase function");
    }
}
