// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AgriculturalInsurance
 * @dev Smart contract for agricultural insurance on Avalanche network
 */
contract AgriculturalInsurance is Ownable, ReentrancyGuard, Pausable {
    
    // Master wallet to receive payments
    address public masterWallet;
    
    // Insurance package structure
    struct InsurancePackage {
        string packageId;
        string name;
        uint256 priceAVAX;  // Price in AVAX (wei)
        uint256 priceUSDC;  // Price in USDC (6 decimals)
        bool isActive;
    }
    
    // Insurance policy structure
    struct InsurancePolicy {
        uint256 policyId;
        address policyholder;
        string packageId;
        uint256 latitude;
        uint256 longitude;
        uint256 startDate;
        uint256 endDate;
        uint256 premiumAmount;
        bool isActive;
        bool isClaimed;
        uint256 createdAt;
    }
    
    // Mapping to store insurance packages
    mapping(string => InsurancePackage) public insurancePackages;
    
    // Mapping to store user policies
    mapping(address => InsurancePolicy[]) public userPolicies;
    
    // Mapping to store policy by ID
    mapping(uint256 => InsurancePolicy) public policies;
    
    // Mapping to store allowed ERC20 tokens
    mapping(address => bool) public allowedERC20Tokens;
    
    // Counter for policy IDs
    uint256 private _policyIdCounter;
    
    // Events for backend integration
    event InsurancePackageCreated(
        string indexed packageId,
        string name,
        uint256 priceAVAX,
        uint256 priceUSDC,
        bool isActive
    );
    
    event InsurancePackageUpdated(
        string indexed packageId,
        string name,
        uint256 priceAVAX,
        uint256 priceUSDC,
        bool isActive
    );
    
    event InsurancePurchased(
        uint256 indexed policyId,
        address indexed policyholder,
        string indexed packageId,
        uint256 latitude,
        uint256 longitude,
        uint256 startDate,
        uint256 endDate,
        uint256 premiumAmount,
        string paymentToken,
        uint256 timestamp
    );
    
    event MasterWalletChanged(
        address indexed oldWallet,
        address indexed newWallet
    );
    
    event ERC20TokenAllowed(
        address indexed tokenAddress,
        bool allowed
    );
    
    event ClaimSubmitted(
        uint256 indexed policyId,
        address indexed policyholder,
        uint256 claimAmount,
        string reason,
        uint256 timestamp
    );
    
    // Modifiers
    modifier validPackage(string memory packageId) {
        require(insurancePackages[packageId].isActive, "Package not found or inactive");
        _;
    }
    
    modifier validPolicy(uint256 policyId) {
        require(policies[policyId].policyId != 0, "Policy not found");
        _;
    }
    
    modifier allowedToken(address tokenAddress) {
        require(allowedERC20Tokens[tokenAddress], "ERC20 token not allowed");
        _;
    }
    
    /**
     * @dev Constructor sets the deployer as owner and master wallet
     */
    constructor() Ownable(msg.sender) {
        masterWallet = msg.sender;
        _policyIdCounter = 1;
        
        // Allow USDC by default
        allowedERC20Tokens[0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E] = true;
    }
    
    /**
     * @dev Purchase insurance with native token (AVAX)
     * @param packageId ID of the insurance package
     * @param latitude Latitude coordinate
     * @param longitude Longitude coordinate
     * @param startDate Start date of insurance coverage
     */
    function purchaseInsuranceWithNative(
        string memory packageId,
        uint256 latitude,
        uint256 longitude,
        uint256 startDate
    ) external payable nonReentrant whenNotPaused validPackage(packageId) {
        require(msg.value == insurancePackages[packageId].priceAVAX, "Incorrect premium amount");
        require(startDate > block.timestamp, "Start date must be in the future");
        
        // Transfer AVAX to master wallet
        (bool success, ) = payable(masterWallet).call{value: msg.value}("");
        require(success, "Failed to transfer AVAX to master wallet");
        
        // Create insurance policy
        uint256 policyId = _policyIdCounter++;
        uint256 endDate = startDate + 365 days; // 1 year coverage
        
        InsurancePolicy memory newPolicy = InsurancePolicy({
            policyId: policyId,
            policyholder: msg.sender,
            packageId: packageId,
            latitude: latitude,
            longitude: longitude,
            startDate: startDate,
            endDate: endDate,
            premiumAmount: msg.value,
            isActive: true,
            isClaimed: false,
            createdAt: block.timestamp
        });
        
        // Store policy
        policies[policyId] = newPolicy;
        userPolicies[msg.sender].push(newPolicy);
        
        // Emit event for backend
        emit InsurancePurchased(
            policyId,
            msg.sender,
            packageId,
            latitude,
            longitude,
            startDate,
            endDate,
            msg.value,
            "AVAX",
            block.timestamp
        );
    }
    
    /**
     * @dev Purchase insurance with ERC20 token
     * @param packageId ID of the insurance package
     * @param tokenAddress ERC20 token address
     * @param latitude Latitude coordinate
     * @param longitude Longitude coordinate
     * @param startDate Start date of insurance coverage
     */
    function purchaseInsuranceWithERC20(
        string memory packageId,
        address tokenAddress,
        uint256 latitude,
        uint256 longitude,
        uint256 startDate
    ) external nonReentrant whenNotPaused validPackage(packageId) allowedToken(tokenAddress) {
        require(startDate > block.timestamp, "Start date must be in the future");
        
        uint256 premiumAmount = insurancePackages[packageId].priceUSDC;
        
        // Transfer ERC20 token from user to master wallet
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transferFrom(msg.sender, masterWallet, premiumAmount),
            "ERC20 transfer failed"
        );
        
        // Create insurance policy
        uint256 policyId = _policyIdCounter++;
        uint256 endDate = startDate + 365 days; // 1 year coverage
        
        InsurancePolicy memory newPolicy = InsurancePolicy({
            policyId: policyId,
            policyholder: msg.sender,
            packageId: packageId,
            latitude: latitude,
            longitude: longitude,
            startDate: startDate,
            endDate: endDate,
            premiumAmount: premiumAmount,
            isActive: true,
            isClaimed: false,
            createdAt: block.timestamp
        });
        
        // Store policy
        policies[policyId] = newPolicy;
        userPolicies[msg.sender].push(newPolicy);
        
        // Emit event for backend
        emit InsurancePurchased(
            policyId,
            msg.sender,
            packageId,
            latitude,
            longitude,
            startDate,
            endDate,
            premiumAmount,
            "ERC20",
            block.timestamp
        );
    }
    
    /**
     * @dev Create or update insurance package (owner only)
     */
    function createOrUpdatePackage(
        string memory packageId,
        string memory name,
        uint256 priceAVAX,
        uint256 priceUSDC,
        bool isActive
    ) external onlyOwner {
        insurancePackages[packageId] = InsurancePackage({
            packageId: packageId,
            name: name,
            priceAVAX: priceAVAX,
            priceUSDC: priceUSDC,
            isActive: isActive
        });
        
        if (policies[1].policyId == 0) {
            emit InsurancePackageCreated(packageId, name, priceAVAX, priceUSDC, isActive);
        } else {
            emit InsurancePackageUpdated(packageId, name, priceAVAX, priceUSDC, isActive);
        }
    }
    
    /**
     * @dev Allow or disallow ERC20 token (owner only)
     */
    function setERC20TokenAllowed(address tokenAddress, bool allowed) external onlyOwner {
        allowedERC20Tokens[tokenAddress] = allowed;
        emit ERC20TokenAllowed(tokenAddress, allowed);
    }
    
    /**
     * @dev Change master wallet (owner only)
     */
    function changeMasterWallet(address newMasterWallet) external onlyOwner {
        require(newMasterWallet != address(0), "Invalid master wallet address");
        address oldWallet = masterWallet;
        masterWallet = newMasterWallet;
        emit MasterWalletChanged(oldWallet, newMasterWallet);
    }
    
    /**
     * @dev Submit claim for insurance policy
     */
    function submitClaim(uint256 policyId, string memory reason) external validPolicy(policyId) {
        InsurancePolicy storage policy = policies[policyId];
        require(policy.policyholder == msg.sender, "Not policy owner");
        require(policy.isActive, "Policy not active");
        require(!policy.isClaimed, "Claim already submitted");
        require(block.timestamp >= policy.startDate, "Insurance not started yet");
        require(block.timestamp <= policy.endDate, "Insurance expired");
        
        policy.isClaimed = true;
        
        emit ClaimSubmitted(
            policyId,
            msg.sender,
            policy.premiumAmount,
            reason,
            block.timestamp
        );
    }
    
    /**
     * @dev Get user's policies
     */
    function getUserPolicies(address user) external view returns (InsurancePolicy[] memory) {
        return userPolicies[user];
    }
    
    /**
     * @dev Get policy by ID
     */
    function getPolicy(uint256 policyId) external view returns (InsurancePolicy memory) {
        return policies[policyId];
    }
    
    /**
     * @dev Get insurance package details
     */
    function getPackage(string memory packageId) external view returns (InsurancePackage memory) {
        return insurancePackages[packageId];
    }
    
    /**
     * @dev Get total number of policies
     */
    function getTotalPolicies() external view returns (uint256) {
        return _policyIdCounter - 1;
    }
    
    /**
     * @dev Check if ERC20 token is allowed
     */
    function isERC20TokenAllowed(address tokenAddress) external view returns (bool) {
        return allowedERC20Tokens[tokenAddress];
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
    
    // Receive function to accept AVAX
    receive() external payable {
        revert("Use purchaseInsuranceWithNative function");
    }
}
