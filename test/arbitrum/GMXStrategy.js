const {
    loadFixture,
    mine,
    time,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

describe.only("GMXStrategy", function () {
    const TOKENS = {
        USDC: {
            address: "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",
            whale: "0x62383739d68dd0f844103db8dfb05a7eded5bbe6",
            decimals: 6,
        },
        ETH: {
            address: ZERO_ADDRESS,
            whale: "0xf977814e90da44bfa03b6295a0616a897441acec",
            decimals: 18,
        },
        DAI: {
            address: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1",
            whale: "0xf0428617433652c9dc6d1093a42adfbf30d29f74",
            decimals: 18,
        },
        GMX: {
            address: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
            whale: "0xb38e8c17e38363af6ebdcb3dae12e0243582891d",
            decimals: 18,
        },
    };

    async function deployContractAndSetVariables() {
        const [deployer, governance, treasury, whale] =
            await ethers.getSigners();
        const USDC_ADDRESS = TOKENS.USDC.address;
        const want = await ethers.getContractAt(IERC20_SOURCE, USDC_ADDRESS);

        const name = "dVault";
        const symbol = "vDeFi";
        const Vault = await ethers.getContractFactory("Vault");
        const vault = await Vault.deploy();
        await vault.deployed();

        await vault["initialize(address,address,address,string,string)"](
            want.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault["setDepositLimit(uint256)"](
            ethers.utils.parseEther("10000")
        );

        const CVXStrategy = await ethers.getContractFactory("GMXStrategy");
        const strategy = await CVXStrategy.deploy(vault.address);
        await strategy.deployed();

        await vault["addStrategy(address,uint256,uint256,uint256,uint256)"](
            strategy.address,
            10000,
            0,
            ethers.utils.parseEther("10000"),
            0
        );

        await dealTokensToAddress(whale.address, TOKENS.USDC, "1000");
        await want
            .connect(whale)
            ["approve(address,uint256)"](
                vault.address,
                ethers.constants.MaxUint256
            );

        return {
            vault,
            deployer,
            want,
            whale,
            governance,
            treasury,
            strategy,
            want,
        };
    }

    async function dealTokensToAddress(
        address,
        dealToken,
        amountUnscaled = "100"
    ) {
        const token = await ethers.getContractAt(
            IERC20_SOURCE,
            dealToken.address
        );

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [dealToken.whale],
        });
        const tokenWhale = await ethers.getSigner(dealToken.whale);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [TOKENS.ETH.whale],
        });
        const ethWhale = await ethers.getSigner(TOKENS.ETH.whale);

        await ethWhale.sendTransaction({
            to: tokenWhale.address,
            value: utils.parseEther("50"),
        });

        await token
            .connect(tokenWhale)
            .transfer(
                address,
                utils.parseUnits(amountUnscaled, dealToken.decimals)
            );
    }

    it("should deploy strategy", async function () {
        const { vault, strategy } = await loadFixture(
            deployContractAndSetVariables
        );
        expect(await strategy.vault()).to.equal(vault.address);
        expect(await strategy.name()).to.equal("StrategyGMX");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.ethToWant(oneUnit))).to.be.greaterThan(0);

        console.log(utils.formatUnits(await strategy.ethToWant(oneUnit), 6));
    });

    it.only("call me", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        await dealTokensToAddress(strategy.address, TOKENS.GMX, "1000");
        await strategy.callMe();
        // await mine(10_000, { interval: 20 });
        await strategy.callMe2();
    });
});
