import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AgriculturalInsurance", (m) => {
  const agriculturalInsurance = m.contract("AgriculturalInsurance");
  
  return { agriculturalInsurance };
});
