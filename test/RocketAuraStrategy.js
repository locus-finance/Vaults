const { loadFixture, mine } = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const dai = "0x6b175474e89094c44da98b954eedeac495271d0f";
const bal = "0xba100000625a3754423978a60c9317c58a424e3D";
const aura = "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF";
const bRethStable = "0x1E19CF2D73a72Ef1332C882F20534B6519Be0276";
const auraBRethStable = "0x001B78CEC62DcFdc660E06A91Eb1bC966541d758";

describe("RocketAuraStrategy", function () {
    async function deployContractAndSetVariables() {
        const [deployer, governance, treasury, whale] = await ethers.getSigners();
        const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
        const want = await ethers.getContractAt("IWETH", WETH_ADDRESS);
        await want.connect(whale).deposit({value: ethers.utils.parseEther("10")});

        const name = "ETH Vault";
        const symbol = "vETH";
        const BaseVault = await ethers.getContractFactory('BaseVault');
        const vault = await BaseVault.deploy();
        await vault.deployed();

        await vault['initialize(address,address,address,string,string)'](
            want.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('10000'))

        const RocketAuraStrategy = await ethers.getContractFactory('RocketAuraStrategy');
        const strategy = await RocketAuraStrategy.deploy(vault.address);
        await strategy.deployed();

        await vault['addStrategy(address,uint256,uint256,uint256,uint256)'](
            strategy.address, 
            10000, 
            0, 
            ethers.utils.parseEther('10000'), 
            0
        );

        return { vault, deployer, symbol, name, want, whale, governance, treasury, strategy, want };
    }

    async function fakeRethPrice(want, fakePrice) {
        const RocketNetworkBalances = await ethers.getContractAt("IRocketNetworkBalances", "0x07fcabcbe4ff0d80c2b1eb42855c0131b6cba2f4");

        await network.provider.send("evm_setAutomine", [false]);
        await network.provider.send("evm_setIntervalMining", [0]);
        const oracles = [
            "0x2c6c5809a257ea74a2df6d20aee6119196d4bea0",
            "0xb13fa6eff52e6db8e9f0f1b60b744a9a9a01425a",
            "0x751683968fd078341c48b90bc657d6babc2339f7", 
            "0xccbff44e0f0329527feb0167bc8744d7d5aed3e9", 
            "0xd7f94c53691afb5a616c6af96e7075c1ffa1d8ee", 
            "0xc5d291607600044348e5014404cc18394bd1d57d", 
            "0xb3a533098485bede3cb7fa8711af84fe0bb1e0ad", 
            "0x58fa2ca71c4a37f6b280fc55e04cc8effa68a18a", 
            "0x16222268bb682aa34ce60c73f4527f30aca1b788", 
            "0x2354628919e1d53d2a69cf700cc53c4093977b94", 
        ];
        const { number } = await hre.ethers.provider.getBlock("latest");
        for (let index = 0; index < oracles.length; index++) {
            const oracleAddress = oracles[index];   
            await network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [oracleAddress],
            });
            const rocketOracle = await ethers.getSigner(oracleAddress);
            await RocketNetworkBalances.connect(rocketOracle).submitBalances(
                number,
                fakePrice, 
                ethers.utils.parseEther('1'), 
                ethers.utils.parseEther('1')
            );
        }
        
        mine(10000);
        await network.provider.send("evm_setAutomine", [true]);

        const wEthWhaleAddress = "0x8eb8a3b98659cce290402893d0123abb75e3ab28";
        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [wEthWhaleAddress],
        });

        const wEthWhale = await ethers.getSigner(wEthWhaleAddress);
        const balancerVault = await ethers.getContractAt("IBalancerV2Vault", "0xBA12222222228d8Ba445958a75a0704d566BF2C8");

        await want.connect(wEthWhale).approve(balancerVault.address, ethers.utils.parseEther('35000'));
        await balancerVault.connect(wEthWhale).swap(
            {
                kind: 0, // SwapKind.GivenIn
                poolId: '0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112',
                assetIn: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
                assetOut: '0xae78736Cd615f374D3085123A210448E74Fc6393',
                amount: ethers.utils.parseEther('350'),
                userData: '0x',
            },
            { 
                sender: wEthWhale.address, 
                recipient: wEthWhale.address, 
                fromInternalBalance: false, 
                toInternalBalance: false 
            },
            0,
            ethers.constants.MaxUint256
        );
    }

    it('should deploy strategy', async function () {
        const { vault, strategy } = await loadFixture(deployContractAndSetVariables);
        expect(await strategy.vault()).to.equal(vault.address);
    });

    it('should harvest with profit', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const balanceBefore = await want.balanceOf(whale.address);
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));
        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.0025'));

        const RocketTokenRETH = await ethers.getContractAt("IRocketTokenRETH", "0xae78736Cd615f374D3085123A210448E74Fc6393");
        await fakeRethPrice(
            want, 
            BigNumber.from((await RocketTokenRETH.getExchangeRate()*1.02).toString())
        );
        mine(36000); // get more rewards
        await strategy.connect(deployer).harvest();
        await vault.connect(whale)['withdraw(uint256)'](ethers.utils.parseEther('10'));

        expect(Number(await want.balanceOf(whale.address))).to.be.greaterThan(Number(balanceBefore));
    });

    it('should withdraw requested amount', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const balanceBefore = await want.balanceOf(whale.address);
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));
        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.0025'));

        await strategy.connect(deployer).harvest();
        await vault.connect(whale)['withdraw(uint256)'](ethers.utils.parseEther('10'));

        expect(await want.balanceOf(whale.address))
        .to.be.closeTo(balanceBefore, ethers.utils.parseEther('0.0025'));
    });

    it('should withdraw with loss', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const balanceBefore = await want.balanceOf(whale.address);
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));

        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();

        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.0025'));

        await strategy.connect(deployer).tend();

        await vault.connect(whale)['withdraw(uint256,address,uint256)'](
            ethers.utils.parseEther('10'), 
            whale.address, 
            5 // 0.05% acceptable loss
        );

        expect(await want.balanceOf(whale.address))
        .to.be.closeTo(balanceBefore, ethers.utils.parseEther('0.0025'));
    });

    it('should not withdraw with loss', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));

        const balanceBefore = await want.balanceOf(whale.address);

        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();

        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.0025'));

        await strategy.connect(deployer).tend();

        await expect( 
            vault.connect(whale)['withdraw(uint256,address,uint256)'](
                ethers.utils.parseEther('10'), 
                whale.address, 
                0 // 0% acceptable loss
            )
        ).to.be.reverted;

        expect(await want.balanceOf(whale.address)).to.equal(balanceBefore);
    });

    it('should emergency exit', async function () {
        const { vault, strategy, whale, want } = await loadFixture(deployContractAndSetVariables); 

        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        expect(await want.balanceOf(vault.address)).to.equal(oneEther);

        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            oneEther, 
            ethers.utils.parseEther('0.0025')
        );

        await strategy.setEmergencyExit();
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.equal(0);
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            oneEther, 
            ethers.utils.parseEther('0.0025')
        );
    });

    it('should sweep', async function () {
        const { vault, deployer, strategy, whale, want } = await loadFixture(deployContractAndSetVariables); 

        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).transfer(strategy.address, oneEther);

        expect(want.address).to.equal(await strategy.want());
        expect(Number(await want.balanceOf(strategy.address))).to.greaterThan(Number(0));

        await expect( 
            strategy.connect(deployer)['sweep(address)'](want.address)
        ).to.be.revertedWith("!want");
        await expect( 
            strategy.connect(deployer)['sweep(address)'](vault.address)
        ).to.be.revertedWith("!shares");
        await expect( 
            strategy.connect(deployer)['sweep(address)'](bRethStable)
        ).to.be.revertedWith("!protected");
        await expect( 
            strategy.connect(deployer)['sweep(address)'](auraBRethStable)
        ).to.be.revertedWith("!protected");
        await expect( 
            strategy.connect(deployer)['sweep(address)'](aura)
        ).to.be.revertedWith("!protected");
        await expect( 
            strategy.connect(deployer)['sweep(address)'](bal)
        ).to.be.revertedWith("!protected");

        const daiToken = await hre.ethers.getContractAt(
            IERC20_SOURCE, 
            dai
        );
        const daiWhaleAddress = "0x60faae176336dab62e284fe19b885b095d29fb7f";
        await network.provider.request({method:"hardhat_impersonateAccount",params:[daiWhaleAddress]});
        const daiWhale = await ethers.getSigner(daiWhaleAddress);

        await daiToken.connect(daiWhale).transfer(
            strategy.address,
            ethers.utils.parseEther("10")
        );
        expect(daiToken.address).not.to.be.equal(await strategy.want());
        await expect( 
            () => strategy.connect(deployer)['sweep(address)'](daiToken.address)
        ).to.changeTokenBalances(
            daiToken,
            [strategy, deployer],
            [ethers.utils.parseEther('-10'), ethers.utils.parseEther('10')]
        );
    });

    it('should change debt', async function () {
        const { vault, strategy, deployer, whale, want } = await loadFixture(deployContractAndSetVariables); 
        
        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        await vault.connect(deployer)['updateStrategyDebtRatio(address,uint256)'](strategy.address, 5000);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('0.5'), 
            ethers.utils.parseEther('0.0025')
        );

        await vault.connect(deployer)['updateStrategyDebtRatio(address,uint256)'](strategy.address, 10000);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );

        await vault.connect(deployer)['updateStrategyDebtRatio(address,uint256)'](strategy.address, 5000);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('0.5'), 
            ethers.utils.parseEther('0.0025')
        );
    });

    it('should trigger', async function () {
        const { vault, strategy, deployer, whale, want } = await loadFixture(deployContractAndSetVariables); 
        
        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        await vault.connect(deployer)['updateStrategyDebtRatio(address,uint256)'](strategy.address, 5000);
        mine(1);
        await strategy.harvest();

        await strategy.harvestTrigger(0);
        await strategy.tendTrigger(0);
    });

    it('should migrate', async function () {
        const { vault, strategy, deployer, whale, want } = await loadFixture(deployContractAndSetVariables); 
        
        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );

        const RocketAuraStrategy = await ethers.getContractFactory('RocketAuraStrategy');
        const newStrategy = await RocketAuraStrategy.deploy(vault.address);
        await newStrategy.deployed();

        const auraToken = await hre.ethers.getContractAt(IERC20_SOURCE, aura);
        const balToken = await hre.ethers.getContractAt(IERC20_SOURCE, bal);
        const bRethStableToken = await hre.ethers.getContractAt(IERC20_SOURCE, bRethStable);
        const auraBRethStableToken = await hre.ethers.getContractAt(IERC20_SOURCE, auraBRethStable);

        await vault['migrateStrategy(address,address)'](strategy.address, newStrategy.address);

        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );
        expect(Number(await auraToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);
        expect(Number(await balToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);
        expect(Number(await bRethStableToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);
        expect(Number(await auraBRethStableToken.balanceOf(newStrategy.address))).to.be.equal(0);

        await newStrategy.harvest();

        expect(Number(await auraToken.balanceOf(newStrategy.address))).to.be.equal(0);
        expect(Number(await balToken.balanceOf(newStrategy.address))).to.be.equal(0);
        expect(Number(await bRethStableToken.balanceOf(newStrategy.address))).to.be.equal(0);
        expect(Number(await auraBRethStableToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);

        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );
    });

    it('should revoke from vault', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );

        await vault['revokeStrategy(address)'](strategy.address);
        mine(1);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            oneEther, 
            ethers.utils.parseEther('0.0025')
        );
    });

    it('should emergency exit', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );

        await strategy['setEmergencyExit()']();
        mine(1);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            oneEther, 
            ethers.utils.parseEther('0.0025')
        );
    });

    it('should withdraw on vault shutdown', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const oneEther = ethers.utils.parseEther('1');
        await want.connect(whale).approve(vault.address, oneEther);
        await vault.connect(whale)['deposit(uint256)'](oneEther);
        expect(await want.balanceOf(vault.address)).to.equal(oneEther);

        if(await want.balanceOf(whale.address) > 0){
            want.connect(whale).transfer(ZERO_ADDRESS, await want.balanceOf(whale.address));
        }
        await strategy.harvest();
        mine(3600*7);

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.0025')
        );

        await vault['setEmergencyShutdown(bool)'](true);
        mine(1);
        await vault.connect(whale)['withdraw()']();
        expect(await want.balanceOf(whale.address)).to.equal(oneEther);
    });
});


