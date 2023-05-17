const {
    loadFixture,
    mine,
    time,
} = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { utils } = require("ethers");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

describe.only("AuraWETHStrategy", function () {
    const TOKENS = {
        USDC: {
            address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            whale: "0xf646d9B7d20BABE204a89235774248BA18086dae",
            decimals: 6,
        },
        ETH: {
            address: ZERO_ADDRESS,
            whale: "0x00000000219ab540356cbb839cbe05303d7705fa",
            decimals: 18,
        },
        DAI: {
            address: "0x6b175474e89094c44da98b954eedeac495271d0f",
            whale: "0x60faae176336dab62e284fe19b885b095d29fb7f",
            decimals: 18,
        },
        AURA: {
            address: "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF",
            whale: "0x39D787fdf7384597C7208644dBb6FDa1CcA4eBdf",
            decimals: 18,
        },
        BAL: {
            address: "0xba100000625a3754423978a60c9317c58a424e3D",
            whale: "0x740a4AEEfb44484853AA96aB12545FC0290805F3",
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

        const AuraWETHStrategy = await ethers.getContractFactory(
            "AuraWETHStrategy"
        );
        const strategy = await AuraWETHStrategy.deploy(vault.address);
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
        expect(await strategy.name()).to.equal("StrategyAuraWETH");
    });

    it("should get reasonable prices from oracle", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        const oneUnit = utils.parseEther("1");

        expect(Number(await strategy.ethToWant(oneUnit))).to.be.greaterThan(0);
        console.log(
            "ETH to want",
            utils.formatUnits(Number(await strategy.ethToWant(oneUnit)), 6)
        );
    });

    it("buying WETH", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        await dealTokensToAddress(strategy.address, TOKENS.USDC, "1000");
        await strategy.buyTokens();

        console.log(utils.formatEther(await strategy.getBptPrice()));
    });

    it("should deposit", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        await dealTokensToAddress(strategy.address, TOKENS.BAL, "1000");
        await strategy.sellBalAndAura(0, 0);
    });

    it.only("gets BPT price", async function () {
        const { strategy } = await loadFixture(deployContractAndSetVariables);
        await dealTokensToAddress(strategy.address, TOKENS.USDC, "1000");
        await strategy.buyTokens();
    });
});
