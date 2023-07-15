import '@nomicfoundation/hardhat-toolbox';

import { HardhatUserConfig } from 'hardhat/config';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {version : "0.8.19"},
      {version : "0.5.16"}
    ]
  },
};

export default config;
