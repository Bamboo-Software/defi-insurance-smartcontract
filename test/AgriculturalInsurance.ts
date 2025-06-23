import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("AgriculturalInsurance", function () {
  let agriculturalInsurance: any;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let masterWallet: SignerWithAddress;

  beforeEach(async function () {
    [owner, user1, user2, masterWallet] = await ethers.getSigners();
    
    const AgriculturalInsuranceFactory = await ethers.getContractFactory("AgriculturalInsurance");
    agriculturalInsurance = await AgriculturalInsuranceFactory.deploy();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await agriculturalInsurance.owner()).to.equal(owner.address);
    });

    it("Should set master wallet to deployer", async function () {
      expect(await agriculturalInsurance.masterWallet()).to.equal(owner.address);
    });

    it("Should allow USDC by default", async function () {
      const usdcAddress = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";
      expect(await agriculturalInsurance.isERC20TokenAllowed(usdcAddress)).to.be.true;
    });
  });

  describe("Insurance Packages", function () {
    it("Should create insurance package", async function () {
      const packageId = "basic-crop-001";
      const name = "Basic Crop Insurance";
      const priceAVAX = ethers.parseEther("0.1"); // 0.1 AVAX
      const priceUSDC = 1000000; // 1 USDC (6 decimals)
      const isActive = true;

      await expect(
        agriculturalInsurance.createOrUpdatePackage(packageId, name, priceAVAX, priceUSDC, isActive)
      )
        .to.emit(agriculturalInsurance, "InsurancePackageCreated")
        .withArgs(packageId, name, priceAVAX, priceUSDC, isActive);

      const insurancePackage = await agriculturalInsurance.getPackage(packageId);
      expect(insurancePackage.name).to.equal(name);
      expect(insurancePackage.priceAVAX).to.equal(priceAVAX);
      expect(insurancePackage.priceUSDC).to.equal(priceUSDC);
      expect(insurancePackage.isActive).to.equal(isActive);
    });

    it("Should update existing package", async function () {
      const packageId = "basic-crop-001";
      const name = "Basic Crop Insurance";
      const priceAVAX = ethers.parseEther("0.1");
      const priceUSDC = 1000000;
      const isActive = true;

      await agriculturalInsurance.createOrUpdatePackage(packageId, name, priceAVAX, priceUSDC, isActive);

      const newPriceAVAX = ethers.parseEther("0.2");
      const newPriceUSDC = 2000000;

      await expect(
        agriculturalInsurance.createOrUpdatePackage(packageId, name, newPriceAVAX, newPriceUSDC, isActive)
      )
        .to.emit(agriculturalInsurance, "InsurancePackageUpdated")
        .withArgs(packageId, name, newPriceAVAX, newPriceUSDC, isActive);

      const insurancePackage = await agriculturalInsurance.getPackage(packageId);
      expect(insurancePackage.priceAVAX).to.equal(newPriceAVAX);
      expect(insurancePackage.priceUSDC).to.equal(newPriceUSDC);
    });
  });

  describe("Insurance Purchase with Native Token", function () {
    beforeEach(async function () {
      const packageId = "basic-crop-001";
      const name = "Basic Crop Insurance";
      const priceAVAX = ethers.parseEther("0.1");
      const priceUSDC = 1000000;
      const isActive = true;

      await agriculturalInsurance.createOrUpdatePackage(packageId, name, priceAVAX, priceUSDC, isActive);
    });

    it("Should purchase insurance with native token", async function () {
      const packageId = "basic-crop-001";
      const latitude = 1000000; // 10.00000
      const longitude = 1060000; // 106.00000
      const startDate = Math.floor(Date.now() / 1000) + 86400; // Tomorrow
      const priceAVAX = ethers.parseEther("0.1");

      const initialBalance = await ethers.provider.getBalance(owner.address);

      await expect(
        agriculturalInsurance.connect(user1).purchaseInsuranceWithNative(
          packageId,
          latitude,
          longitude,
          startDate,
          { value: priceAVAX }
        )
      )
        .to.emit(agriculturalInsurance, "InsurancePurchased")
        .withArgs(
          1, // policyId
          user1.address,
          packageId,
          latitude,
          longitude,
          startDate,
          startDate + 365 * 24 * 60 * 60, // endDate
          priceAVAX,
          "AVAX",
          await agriculturalInsurance.getTotalPolicies()
        );

      const finalBalance = await ethers.provider.getBalance(owner.address);
      expect(finalBalance).to.be.gt(initialBalance);

      const policies = await agriculturalInsurance.getUserPolicies(user1.address);
      expect(policies.length).to.equal(1);
      expect(policies[0].policyId).to.equal(1);
      expect(policies[0].policyholder).to.equal(user1.address);
    });

    it("Should fail with incorrect premium amount", async function () {
      const packageId = "basic-crop-001";
      const latitude = 1000000;
      const longitude = 1060000;
      const startDate = Math.floor(Date.now() / 1000) + 86400;
      const wrongPrice = ethers.parseEther("0.05"); // Wrong amount

      await expect(
        agriculturalInsurance.connect(user1).purchaseInsuranceWithNative(
          packageId,
          latitude,
          longitude,
          startDate,
          { value: wrongPrice }
        )
      ).to.be.revertedWith("Incorrect premium amount");
    });

    it("Should fail with past start date", async function () {
      const packageId = "basic-crop-001";
      const latitude = 1000000;
      const longitude = 1060000;
      const startDate = Math.floor(Date.now() / 1000) - 86400; // Yesterday
      const priceAVAX = ethers.parseEther("0.1");

      await expect(
        agriculturalInsurance.connect(user1).purchaseInsuranceWithNative(
          packageId,
          latitude,
          longitude,
          startDate,
          { value: priceAVAX }
        )
      ).to.be.revertedWith("Start date must be in the future");
    });
  });

  describe("ERC20 Token Management", function () {
    it("Should allow owner to set ERC20 token allowed", async function () {
      const tokenAddress = "0x1234567890123456789012345678901234567890";
      
      await expect(
        agriculturalInsurance.setERC20TokenAllowed(tokenAddress, true)
      )
        .to.emit(agriculturalInsurance, "ERC20TokenAllowed")
        .withArgs(tokenAddress, true);

      expect(await agriculturalInsurance.isERC20TokenAllowed(tokenAddress)).to.be.true;
    });

    it("Should disallow ERC20 token", async function () {
      const tokenAddress = "0x1234567890123456789012345678901234567890";
      
      await agriculturalInsurance.setERC20TokenAllowed(tokenAddress, true);
      await agriculturalInsurance.setERC20TokenAllowed(tokenAddress, false);

      expect(await agriculturalInsurance.isERC20TokenAllowed(tokenAddress)).to.be.false;
    });

    it("Should fail when non-owner tries to set ERC20 token allowed", async function () {
      const tokenAddress = "0x1234567890123456789012345678901234567890";
      
      await expect(
        agriculturalInsurance.connect(user1).setERC20TokenAllowed(tokenAddress, true)
      ).to.be.revertedWithCustomError(agriculturalInsurance, "OwnableUnauthorizedAccount");
    });
  });

  describe("Master Wallet Management", function () {
    it("Should change master wallet", async function () {
      await expect(
        agriculturalInsurance.changeMasterWallet(masterWallet.address)
      )
        .to.emit(agriculturalInsurance, "MasterWalletChanged")
        .withArgs(owner.address, masterWallet.address);

      expect(await agriculturalInsurance.masterWallet()).to.equal(masterWallet.address);
    });

    it("Should fail to change master wallet to zero address", async function () {
      await expect(
        agriculturalInsurance.changeMasterWallet(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid master wallet address");
    });

    it("Should fail when non-owner tries to change master wallet", async function () {
      await expect(
        agriculturalInsurance.connect(user1).changeMasterWallet(masterWallet.address)
      ).to.be.revertedWithCustomError(agriculturalInsurance, "OwnableUnauthorizedAccount");
    });
  });

  describe("Contract Pausing", function () {
    it("Should pause and unpause contract", async function () {
      await agriculturalInsurance.pause();
      expect(await agriculturalInsurance.paused()).to.be.true;

      await agriculturalInsurance.unpause();
      expect(await agriculturalInsurance.paused()).to.be.false;
    });

    it("Should fail to purchase when paused", async function () {
      const packageId = "basic-crop-001";
      const name = "Basic Crop Insurance";
      const priceAVAX = ethers.parseEther("0.1");
      const priceUSDC = 1000000;
      const isActive = true;

      await agriculturalInsurance.createOrUpdatePackage(packageId, name, priceAVAX, priceUSDC, isActive);
      await agriculturalInsurance.pause();

      const latitude = 1000000;
      const longitude = 1060000;
      const startDate = Math.floor(Date.now() / 1000) + 86400;

      await expect(
        agriculturalInsurance.connect(user1).purchaseInsuranceWithNative(
          packageId,
          latitude,
          longitude,
          startDate,
          { value: priceAVAX }
        )
      ).to.be.revertedWithCustomError(agriculturalInsurance, "EnforcedPause");
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow emergency AVAX withdrawal", async function () {
      // Send some AVAX to contract
      await user1.sendTransaction({
        to: await agriculturalInsurance.getAddress(),
        value: ethers.parseEther("1")
      });

      const initialBalance = await ethers.provider.getBalance(owner.address);
      await agriculturalInsurance.emergencyWithdraw();
      const finalBalance = await ethers.provider.getBalance(owner.address);

      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should fail emergency withdrawal when no AVAX", async function () {
      await expect(
        agriculturalInsurance.emergencyWithdraw()
      ).to.be.revertedWith("No AVAX to withdraw");
    });
  });
});
