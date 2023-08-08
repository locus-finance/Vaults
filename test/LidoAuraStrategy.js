const { loadFixture, mine, reset } = require("@nomicfoundation/hardhat-network-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const { expect } = require("chai");
const { constants } = require("ethers");
const { ethers } = require("hardhat");

const { getEnv } = require("../scripts/utils");

const IERC20_SOURCE = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7";
const dai = "0x6b175474e89094c44da98b954eedeac495271d0f";
const bal = "0xba100000625a3754423978a60c9317c58a424e3D";
const aura = "0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF";
const bStethStable = "0x32296969Ef14EB0c6d29669C550D4a0449130230";
const auraBStethStable = "0x59d66c58e83a26d6a0e35114323f65c3945c89c1";

const ETH_NODE_URL = getEnv("ETH_NODE");
const ETH_FORK_BLOCK = getEnv("ETH_FORK_BLOCK");

describe("LidoAuraStrategy", function () {
    async function deployContractAndSetVariables() {
        await reset(ETH_NODE_URL, Number(ETH_FORK_BLOCK));

        const [deployer, governance, treasury, whale] = await ethers.getSigners();
        const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
        const want = await ethers.getContractAt("IWETH", WETH_ADDRESS);
        await want.connect(whale).deposit({value: ethers.utils.parseEther("100")});

        const name = "ETH Vault";
        const symbol = "vlETH";
        const Vault = await ethers.getContractFactory('Vault');
        const vault = await Vault.deploy();
        await vault.deployed();

        await vault['initialize(address,address,address,string,string)'](
            want.address,
            deployer.address,
            treasury.address,
            name,
            symbol
        );
        await vault['setDepositLimit(uint256)'](ethers.utils.parseEther('10000'))

        const LidoAuraStrategy = await ethers.getContractFactory('LidoAuraStrategy');
        const strategy = await LidoAuraStrategy.deploy(vault.address);
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

    it('should deploy strategy', async function () {
        const { vault, strategy } = await loadFixture(deployContractAndSetVariables);
        expect(await strategy.vault()).to.equal(vault.address);
    });

    it('should harvest with profit', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));
        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();
        const balanceBefore = await want.balanceOf(whale.address);
        const estimatedBefore = await strategy.estimatedTotalAssets();

        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.2'));

        for (let index = 0; index < 15; index++) {
            mine(38000); // get more rewards
        }
        await strategy.connect(deployer).harvest();

        expect(Number(await strategy.estimatedTotalAssets()))
        .to.be.greaterThan(Number(estimatedBefore));
        await vault.connect(whale)['withdraw(uint256,address,uint256)'](
            ethers.utils.parseEther('10'), 
            whale.address, 
            5 // 0.05% acceptable loss
        );

        expect(Number(await want.balanceOf(whale.address))).to.be.greaterThan(Number(balanceBefore));
    });

    it('should set bpt slippage', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 
        
        expect(await strategy.bptSlippage()).to.be.not.equal(9999);
        await strategy.connect(deployer)['setBptSlippage(uint256)'](9999);
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        expect(await strategy.bptSlippage()).to.be.equal(9999);
    });

    it('should fail harvest with small rewards slippage', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        await strategy.connect(deployer)['setRewardsSlippage(uint256)'](9999);
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('10'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('10'));
        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('10'));

        await strategy.connect(deployer).harvest();
        mine(38000); // get more rewards

        await expect(strategy.connect(deployer).harvest()).to.be.reverted;

        await strategy.connect(deployer)['setRewardsSlippage(uint256)'](9000);
        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('10'), ethers.utils.parseEther('0.2'));
    });

    it('should withdraw requested amount', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const balanceBefore = await want.balanceOf(whale.address);
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('100'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('100'));
        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('100'));

        await strategy.connect(deployer).harvest();
        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('100'), ethers.utils.parseEther('2.5'));

        await strategy.connect(deployer).harvest();
        await vault.connect(whale)['withdraw(uint256,address,uint256)'](
            ethers.utils.parseEther('100'), 
            whale.address, 
            3 // 0.03% acceptable loss
        );

        expect(await want.balanceOf(whale.address))
        .to.be.closeTo(balanceBefore, ethers.utils.parseEther('2.5'));
    });

    it('should withdraw with loss', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        const balanceBefore = await want.balanceOf(whale.address);
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('100'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('100'));

        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('100'));

        await strategy.connect(deployer).harvest();

        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('100'), ethers.utils.parseEther('2'));

        await strategy.connect(deployer).tend();

        await vault.connect(whale)['withdraw(uint256,address,uint256)'](
            ethers.utils.parseEther('100'), 
            whale.address, 
            10 // 0.1% acceptable loss
        );

        expect(await want.balanceOf(whale.address))
        .to.be.closeTo(balanceBefore, ethers.utils.parseEther('2'));
    });

    it('should not withdraw with loss', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('100'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('100'));

        const balanceBefore = await want.balanceOf(whale.address);

        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('100'));

        await strategy.connect(deployer).harvest();

        expect(await strategy.estimatedTotalAssets())
        .to.be.closeTo(ethers.utils.parseEther('100'), ethers.utils.parseEther('2'));

        await strategy.connect(deployer).tend();

        await expect( 
            vault.connect(whale)['withdraw(uint256,address,uint256)'](
                ethers.utils.parseEther('100'), 
                whale.address, 
                0 // 0% acceptable loss
            )
        ).to.be.reverted;

        expect(await want.balanceOf(whale.address)).to.equal(balanceBefore);
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
            strategy.connect(deployer)['sweep(address)'](bStethStable)
        ).to.be.revertedWith("!protected");
        await expect( 
            strategy.connect(deployer)['sweep(address)'](auraBStethStable)
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
            ethers.utils.parseEther('0.025')
        );

        await vault.connect(deployer)['updateStrategyDebtRatio(address,uint256)'](strategy.address, 10000);
        mine(1000);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.025')
        );

        await vault.connect(deployer)['updateStrategyDebtRatio(address,uint256)'](strategy.address, 5000);
        mine(1000);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('0.5'), 
            ethers.utils.parseEther('0.025')
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

        await strategy.harvest();
        mine(1000);

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.025')
        );

        const LidoAuraStrategy = await ethers.getContractFactory('LidoAuraStrategy');
        const newStrategy = await LidoAuraStrategy.deploy(vault.address);
        await newStrategy.deployed();

        const auraToken = await hre.ethers.getContractAt(IERC20_SOURCE, aura);
        const balToken = await hre.ethers.getContractAt(IERC20_SOURCE, bal);
        const bStethStableToken = await hre.ethers.getContractAt(IERC20_SOURCE, bStethStable);
        const auraBStethStableToken = await hre.ethers.getContractAt(IERC20_SOURCE, auraBStethStable);

        await vault['migrateStrategy(address,address)'](strategy.address, newStrategy.address);

        expect(await strategy.estimatedTotalAssets()).to.be.equal(0);
        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.025')
        );
        expect(Number(await auraToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);
        expect(Number(await balToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);
        expect(Number(await bStethStableToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);
        expect(Number(await auraBStethStableToken.balanceOf(newStrategy.address))).to.be.equal(0);

        await newStrategy.harvest();

        expect(Number(await auraToken.balanceOf(newStrategy.address))).to.be.equal(0);
        expect(Number(await balToken.balanceOf(newStrategy.address))).to.be.equal(0);
        expect(Number(await bStethStableToken.balanceOf(newStrategy.address))).to.be.equal(0);
        expect(Number(await auraBStethStableToken.balanceOf(newStrategy.address))).to.be.greaterThan(0);

        expect(await newStrategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('1'), 
            ethers.utils.parseEther('0.025')
        );
    });

    it('should revoke from vault', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('100'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('100'));
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('100'), 
            ethers.utils.parseEther('2')
        );

        await vault['revokeStrategy(address)'](strategy.address);
        mine(1);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            ethers.utils.parseEther('100'), 
            ethers.utils.parseEther('2')
        );
    });

    it('should emergency exit', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('100'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('100'));
        mine(1);
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('100'), 
            ethers.utils.parseEther('2')
        );

        await strategy['setEmergencyExit()']();
        mine(1);
        await strategy.harvest();
        expect(await want.balanceOf(vault.address)).to.be.closeTo(
            ethers.utils.parseEther('100'), 
            ethers.utils.parseEther('2')
        );
    });

    it('should withdraw on vault shutdown', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 

        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('100'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('100'));
        expect(await want.balanceOf(vault.address)).to.equal(ethers.utils.parseEther('100'));

        if(await want.balanceOf(whale.address) > 0){
            want.connect(whale).transfer(ZERO_ADDRESS, await want.balanceOf(whale.address));
        }
        await strategy.harvest();

        expect(await strategy.estimatedTotalAssets()).to.be.closeTo(
            ethers.utils.parseEther('100'), 
            ethers.utils.parseEther('2')
        );

        await vault['setEmergencyShutdown(bool)'](true);
        await vault.connect(whale)['withdraw(uint256,address,uint256)'](
            ethers.utils.parseEther('100'), 
            whale.address, 
            8 // 0.05% acceptable loss
        );
        expect(await want.balanceOf(whale.address)).to.be.closeTo(
            ethers.utils.parseEther('100'), 
            ethers.utils.parseEther('2')
        );
    });

    it('should not liquidate when enough want', async function () {
        const { vault, strategy, whale, deployer, want } = await loadFixture(deployContractAndSetVariables); 
        
        await want.connect(whale).approve(vault.address, ethers.utils.parseEther('1'));
        await vault.connect(whale)['deposit(uint256)'](ethers.utils.parseEther('1'));

        await strategy.connect(deployer).harvest();
        const balanceBefore = await strategy.estimatedTotalAssets();

        want.connect(whale).transfer(strategy.address, ethers.utils.parseEther('8'));

        await expect(vault.connect(whale)['withdraw()']()).not.to.be.reverted;
    });

    it("should change AURA PID and AURA rewards", async function () {
        const { strategy, whale, deployer } = await loadFixture(
            deployContractAndSetVariables
        );

        expect(await strategy.AURA_PID()).to.be.equal(115);
        await expect(strategy.connect(whale)["setAuraPid(uint256)"](200)).to.be
            .reverted;
        await strategy.connect(deployer)["setAuraPid(uint256)"](200);
        expect(await strategy.AURA_PID()).to.be.equal(200);

        expect(
            (await strategy.auraBStethStable()).toLocaleLowerCase()
        ).to.be.equal(auraBStethStable.toLocaleLowerCase());
        await expect(
            strategy
                .connect(whale)
                ["setAuraBStethStable(address)"](constants.AddressZero)
        ).to.be.reverted;
        await strategy
            .connect(deployer)
            ["setAuraBStethStable(address)"](constants.AddressZero);
        expect(await strategy.auraBStethStable()).to.be.equal(
            constants.AddressZero
        );
    });
});
