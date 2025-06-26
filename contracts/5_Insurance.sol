// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

library InternalLib {
  function intToStringWithDecimal(int32 _value) internal pure returns (string memory) {
    if (_value == 0) return "0.000000";
    bool negative = _value < 0;
    uint32 absValue = uint32(negative ? -_value : _value);
    uint32 integerPart = absValue / 1_000_000;
    uint32 decimalPart = absValue % 1_000_000;
    string memory intStr = _toString(integerPart);
    string memory decStr = _toString(decimalPart);
    while (bytes(decStr).length < 6) {
      decStr = string(abi.encodePacked("0", decStr));
    }
    return
      negative ? string(abi.encodePacked("-", intStr, ".", decStr)) : string(abi.encodePacked(intStr, ".", decStr));
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
}

/**
 * @title AgriculturalInsurance
 * @dev Smart contract for agricultural insurance on Avalanche network
 */
contract AgriculturalInsurance is Ownable, ReentrancyGuard, Pausable, FunctionsClient, AutomationCompatibleInterface {
  using FunctionsRequest for FunctionsRequest.Request;
  using InternalLib for int32;
  uint64 public subscriptionId;

  bytes32 public s_lastRequestId;
  bytes public s_lastResponse;
  bytes public s_lastError;

  error UnexpectedRequestID(bytes32 requestId);

  event WeatherResponse(bytes32 indexed requestId, bytes response);
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
  event EmergencyWithdraw(address indexed owner, uint256 amount, string tokenType);
  event Log(uint8 logType, string message);
  event PayoutProcessed(address indexed user, string claimId, uint256 amount, string tokenType);

  address router = 0xA9d587a00A31A52Ed70D6026794a8FC5E2F5dCb0;
  string source =
    "const lat = parseFloat(args[0]);"
    "const lng = parseFloat(args[1]);"
    "const apiKey = '3fphyWwq46y28GTX9a6yDwS2lKEUpuBI';"
    "const apiResponse = await Functions.makeHttpRequest({"
    "  url: `https://api.tomorrow.io/v4/weather/realtime`,"
    "  params: {"
    "    location: `${lat},${lng}`,"
    "    apikey: apiKey,"
    "  },"
    "});"
    "if (apiResponse.error) {"
    "  const errorDetails = JSON.stringify(apiResponse, null, 2);"
    "  console.error('Request failed:', errorDetails);"
    "  throw Error(`Request failed: ${errorDetails}`);"
    "}"
    "const weather = apiResponse.data?.data?.values;"
    "if (!weather) {"
    '  throw Error("No weather data received");'
    "}"
    "const essentialData = {"
    "  lat,"
    "  lng,"
    "  temperature: weather.temperature,"
    "  rainIntensity: weather.rainIntensity,"
    "  precipitationProbability: weather.precipitationProbability,"
    "  humidity: weather.humidity,"
    "  windSpeed: weather.windSpeed,"
    "  timestamp: apiResponse.data?.data?.time,"
    "};"
    "console.log('Weather data:', JSON.stringify(essentialData, null, 2));"
    "return Functions.encodeString(JSON.stringify(essentialData));";

  uint32 gasLimit = 300000;
  bytes32 donID = 0x66756e2d6176616c616e6368652d66756a692d31000000000000000000000000;
  string public character;
  address public masterWallet;

  struct CompactLocation {
    int32 lat;
    int32 lon;
  }
  mapping(bytes32 => CompactLocation) public locations;
  mapping(bytes32 => bool) public isActive;
  bytes32[] public locationKeys;
  mapping(address => bool) public allowedERC20Tokens;
  mapping(bytes32 => mapping(bytes32 => int256)) public weatherDataByLocation;

  modifier allowedToken(address tokenAddress) {
    require(allowedERC20Tokens[tokenAddress], "ERC20 token not allowed");
    _;
  }

  /**
   * @dev Constructor sets the deployer as owner and master wallet
   */
  constructor() FunctionsClient(router) Ownable(msg.sender) {
    masterWallet = msg.sender;
    subscriptionId = 15649;
    allowedERC20Tokens[0x5425890298aed601595a70AB815c96711a31Bc65] = true;
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
    // (bool sent, ) = masterWallet.call{ value: msg.value }("");
    // require(sent, "Failed to send AVAX");

    // Giữ lại AVAX trong contract, không chuyển đi đâu cả
    addLocation(lat, lon);
    emit InsurancePurchased(msg.sender, packageId, address(0), msg.value, lat, lon, startDate, "AVAX", block.timestamp);
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
    // require(token.transferFrom(msg.sender, masterWallet, premiumAmount), "ERC20 transfer failed");
    require(token.transferFrom(msg.sender, address(this), premiumAmount), "ERC20 transfer failed");

    // Giữ lại token trong contract, không chuyển đi đâu cả
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
   * @notice Sends an HTTP request for weather information
   * @param args The arguments to pass to the HTTP request
   * @return requestId The ID of the request
   */
  function sendRequest(string[] memory args) internal returns (bytes32 requestId) {
    require(subscriptionId != 0, "Subscription ID not set");
    FunctionsRequest.Request memory req;
    req.initializeRequestForInlineJavaScript(source);
    if (args.length > 0) req.setArgs(args);
    s_lastRequestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
    return s_lastRequestId;
  }

  /**
   * @notice Callback function for fulfilling a request
   * @param requestId The ID of the request to fulfill
   * @param response The HTTP response data
   * @param err Any errors from the Functions request
   */
  function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
    if (s_lastRequestId != requestId) {
      revert UnexpectedRequestID(requestId);
    }
    // Không lưu storage nếu không cần dùng lại
    // s_lastResponse = response;
    // s_lastError = err;

    emit WeatherResponse(requestId, response);
  }

  /**
   * @dev Check if upkeep is needed by checking for active locations
   */
  function checkUpkeep(
    bytes calldata /* checkData */
  ) external view override returns (bool upkeepNeeded, bytes memory performData) {
    upkeepNeeded = locationKeys.length > 0;
    performData = abi.encode(locationKeys);
    return (upkeepNeeded, performData);
  }

  /**
   * @dev Perform upkeep by requesting weather data for all active locations
   */
  function performUpkeep(bytes calldata performData) external override {
    require(subscriptionId != 0, "Subscription ID not set");
    bytes32[] memory keys = abi.decode(performData, (bytes32[]));
    for (uint256 i = 0; i < keys.length; i++) {
      bytes32 key = keys[i];
      if (isActive[key]) {
        CompactLocation memory loc = locations[key];
        string[] memory args = new string[](2);
        args[0] = loc.lat.intToStringWithDecimal();
        args[1] = loc.lon.intToStringWithDecimal();
        bytes32 requestId = sendRequest(args);
        emit WeatherDataRequested(requestId, loc.lat, loc.lon);
      }
    }
  }

  /**
   * @dev Fetch weather data for all active locations (for Time-based Upkeep)
   */
  function fetchWeatherData() external whenNotPaused {
    require(subscriptionId != 0, "Subscription ID not set");
    for (uint256 i = 0; i < locationKeys.length; i++) {
      bytes32 key = locationKeys[i];
      if (isActive[key]) {
        CompactLocation memory loc = locations[key];
        string[] memory args = new string[](2);
        args[0] = loc.lat.intToStringWithDecimal();
        args[1] = loc.lon.intToStringWithDecimal();
        bytes32 requestId = sendRequest(args);
        emit WeatherDataRequested(requestId, loc.lat, loc.lon);
      }
    }
  }

  /**
   * @dev Process payout for a user with a claim ID
   * @param user The address of the user to receive the payout
   * @param claimId The unique ID of the claim
   * @param amount The amount of the payout
   * @param tokenAddress The address of the token to pay out (or address(0) for AVAX)
   */
  function processPayout(
    address user,
    string memory claimId,
    uint256 amount,
    address tokenAddress
  ) external onlyOwner nonReentrant {
    require(user != address(0), "Invalid user address");
    require(amount > 0, "Payout amount must be greater than 0");
    require(bytes(claimId).length > 0, "Invalid claim ID");
    if (tokenAddress == address(0)) {
      require(address(this).balance >= amount, "AVAX balance is not enough");
      (bool sent, ) = user.call{ value: amount }("");
      require(sent, "Failed to send AVAX");
    } else {
      require(allowedERC20Tokens[tokenAddress], "Token ERC20 not allowed");
      IERC20 token = IERC20(tokenAddress);
      require(token.balanceOf(address(this)) >= amount, "Token balance is not enough");
      require(token.transfer(user, amount), "Failed to transfer token");
    }
    emit Log(0, string(abi.encodePacked("Processed payout for claim: ", claimId)));
    emit PayoutProcessed(user, claimId, amount, tokenAddress == address(0) ? "AVAX" : "ERC20");
  }

  /**
   * @dev Update subscriptionId (owner only)
   * @param _subscriptionId New subscription ID for Chainlink Functions
   */
  function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
    require(_subscriptionId != 0, "Invalid subscription ID");
    subscriptionId = _subscriptionId;
    emit Log(0, "Subscription ID updated");
  }

  /**
   * @dev Add location and mark as active
   * @param lat Latitude coordinate (int32)
   * @param lon Longitude coordinate (int32)
   */
  function addLocation(int32 lat, int32 lon) internal {
    bytes32 key = keccak256(abi.encode(lat, lon));
    if (lat < -90000000 || lat > 90000000) {
      emit Log(1, string(abi.encodePacked("Invalid latitude: ", lat.intToStringWithDecimal())));
      revert("Invalid latitude");
    }
    if (lon < -180000000 || lon > 180000000) {
      emit Log(1, string(abi.encodePacked("Invalid longitude: ", lon.intToStringWithDecimal())));
      revert("Invalid longitude");
    }
    if (!isActive[key]) {
      locations[key] = CompactLocation(lat, lon);
      isActive[key] = true;
      locationKeys.push(key);
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
   * @dev Get all active locations
   * @return An array of CompactLocation structs
   */
  function getAllActiveLocations() external view returns (CompactLocation[] memory) {
    uint256 count = 0;
    for (uint256 i = 0; i < locationKeys.length; i++) {
      if (isActive[locationKeys[i]]) {
        count++;
      }
    }
    CompactLocation[] memory result = new CompactLocation[](count);
    uint256 j = 0;
    for (uint256 i = 0; i < locationKeys.length; i++) {
      if (isActive[locationKeys[i]]) {
        result[j] = locations[locationKeys[i]];
        j++;
      }
    }
    return result;
  }

  function emergencyWithdrawAVAX(uint256 amount) external onlyOwner {
    uint256 balance = address(this).balance;
    require(balance >= amount && amount > 0, "Invalid withdraw amount");
    (bool sent, ) = owner().call{ value: amount }("");
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

  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @dev Unpause contract (owner only)
   */
  function unpause() external onlyOwner {
    _unpause();
  }

  receive() external payable {}
}
