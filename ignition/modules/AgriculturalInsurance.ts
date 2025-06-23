import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AgriculturalInsurance", (m) => {
  const agriculturalInsurance = m.contract("AgriculturalInsurance");
  
  // Tạo gói bảo hiểm mẫu
  m.call(agriculturalInsurance, "createOrUpdatePackage", [
    "basic-crop-001", // packageId
    "Basic Crop Insurance", // name
    "100000000000000000", // priceAVAX (0.1 AVAX in wei)
    "1000000", // priceUSDC (1 USDC = 1,000,000 wei)
    true // isActive
  ]);
  
  return { agriculturalInsurance };
});
