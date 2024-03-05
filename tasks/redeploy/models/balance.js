const hre = require("hardhat");
const { DataTypes } = require('sequelize');

module.exports = (connection, decimals) => connection.define(
  'Balance',
  {
    vault_addr: {
      type: DataTypes.TEXT,
      isLowercase: true
    },
    network: {
      type: DataTypes.TEXT
    },
    user_addr: {
      type: DataTypes.TEXT,
      get() {
        const rawValue = this.getDataValue('user_addr');
        return rawValue ? hre.ethers.utils.getAddress(rawValue) : null; // cast to checksum address for comparison
      }
    },
    amount: {
      type: DataTypes.FLOAT(4),
      get() {
        const rawValue = this.getDataValue('amount');
        return rawValue 
          ? hre.ethers.utils.parseUnits(
              rawValue.toString().substring(0, decimals).replace(",", ""), 
              decimals
            ) 
          : null; // cast to BigNumber for comparison
      }
    },
    created_at: {
      type: DataTypes.TIME
    }
  },
  {
    tableName: 'balances',
    timestamps: false
  }
);