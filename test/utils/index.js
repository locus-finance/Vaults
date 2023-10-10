const { ethers } = require("hardhat");

module.exports = {
    toBytes32(bn) {
        return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
    },
    async setStorageAt(address, index, value) {
        await ethers.provider.send("hardhat_setStorageAt", [
            address,
            index,
            value,
        ]);
        await ethers.provider.send("evm_mine", []);
    },
};
