// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";
import "../interfaces/ICToken.sol";
import "../interfaces/IBalancerV2Vault.sol";
import "../interfaces/IBalancerPool.sol";
import "../interfaces/IBalancerPriceOracle.sol";
import "../interfaces/IRocketTokenRETH.sol";
import "../interfaces/IAuraBooster.sol";
import "../interfaces/IAuraDeposit.sol";
import "../interfaces/IAuraRewards.sol";
import "../interfaces/IConvexRewards.sol";
import "../interfaces/ICvx.sol";
import "../interfaces/IAuraToken.sol";
import "../interfaces/IAuraMinter.sol";

import "../utils/AuraMath.sol";

contract RocketAuraStrategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using AuraMath for uint256;

    address internal constant bRethStable = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    address internal constant auraBRethStable = 0x001B78CEC62DcFdc660E06A91Eb1bC966541d758;
    address internal constant auraToken = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address internal constant balToken = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant auraBooster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;

    IBalancerV2Vault internal constant balancerVault = IBalancerV2Vault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    // @TODO remove IRocketTokenRETH
    IRocketTokenRETH internal constant rETH = IRocketTokenRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);
    // IAuraDeposit internal constant auraBooster = IAuraDeposit(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);    

    // @TODO retrieve with pool.getPoolId() instead of hard-code
    bytes32 internal constant poolId = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;

    //@TODO allow changing
    uint256 public slippage = 9800; // 2%

    bytes32 internal constant balEthPoolId = 
        bytes32(0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014);
    bytes32 internal constant auraEthPoolId = 
        bytes32(0xc29562b045d80fd77c69bec09541f5c16fe20d9d000200000000000000000251);

    constructor(address _vault) BaseStrategy(_vault) {
        want.approve(address(balancerVault), type(uint256).max);
        IBalancerPool(bRethStable).approve(auraBooster, type(uint256).max);
        IERC20(auraToken).approve(address(balancerVault), type(uint256).max);
        IERC20(balToken).approve(address(balancerVault), type(uint256).max);
    }

    function name() external view override returns (string memory) {
        return "StrategyRocketAura";
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    /// @notice Balance of want sitting in our strategy.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfAuraBpt() public view returns (uint256) {
        return IERC20(auraBRethStable).balanceOf(address(this));
    }

    function balanceOfUnstakedBpt() public view returns (uint256) {
        return IBalancerPool(bRethStable).balanceOf(address(this));
    }

    function balRewards() public view returns (uint256) {
        return IAuraRewards(auraBRethStable).earned(address(this));
    }

    function auraRewards(uint256 _balRewards) public view returns (uint256) {
        return convertCrvToCvx(_balRewards);
    }

    function auraBptToBpt(uint _amountAuraBpt) public pure returns (uint256) {
        return _amountAuraBpt;
    }

    /// use bpt rate to estimate equivalent amount of want.
    function bptsToWant(uint _amountBpt) public view returns (uint _amount){
        // replace getRate to oracle use like in getBalPrice()
        uint unscaled = _amountBpt.mul(IBalancerPool(bRethStable).getRate()).div(1e18);
        return _scaleDecimals(unscaled, ERC20(bRethStable), ERC20(address(want)));
    }

    /// use bpt rate to estimate equivalent amount of bpt.
    function wantToBpts(uint _amountWant) public view returns (uint _amount){
        // replace getRate to oracle use like in getBalPrice()
        uint unscaled = _amountWant.mul(1e18).div(IBalancerPool(bRethStable).getRate());
        return _scaleDecimals(unscaled, ERC20(address(want)), ERC20(bRethStable));
    }

    function _scaleDecimals(uint _amount, ERC20 _fromToken, ERC20 _toToken) internal view returns (uint _scaled){
        uint decFrom = _fromToken.decimals();
        uint decTo = _toToken.decimals();
        return decTo > decFrom ? _amount.mul(10 ** (decTo.sub(decFrom))) : _amount.div(10 ** (decFrom.sub(decTo)));
    }

    // @notice Only works until inflationProtectionTime has passed
    // https://github.com/aurafinance/aura-contracts/pull/164#discussion_r1115144094
    function convertCrvToCvx(uint256 _amount) internal view returns (uint256 amount) {
        address minter = IAuraToken(auraToken).minter();
        uint256 inflationProtectionTime = IAuraMinter(minter).inflationProtectionTime();
        // console.log("inflationProtectionTime");
        // console.log(inflationProtectionTime);
        // console.log("block.timestamp");
        // console.log(block.timestamp);

        if(block.timestamp > inflationProtectionTime){
            // Inflation protected for now
            return 0;
        }

        uint256 supply = ICvx(auraToken).totalSupply();
        uint256 totalCliffs = ICvx(auraToken).totalCliffs();
        uint256 maxSupply = ICvx(auraToken).EMISSIONS_MAX_SUPPLY();
        uint256 initMintAmount = ICvx(auraToken).INIT_MINT_AMOUNT();

        // After AuraMinter.inflationProtectionTime has passed, this calculation might not be valid.
        // uint256 emissionsMinted = supply - initMintAmount - minterMinted;
        uint256 emissionsMinted = supply - initMintAmount;

        uint256 cliff = emissionsMinted.div(ICvx(auraToken).reductionPerCliff());

        // e.g. 100 < 500
        if (cliff < totalCliffs) {
            // e.g. (new) reduction = (500 - 100) * 2.5 + 700 = 1700;
            // e.g. (new) reduction = (500 - 250) * 2.5 + 700 = 1325;
            // e.g. (new) reduction = (500 - 400) * 2.5 + 700 = 950;
            uint256 reduction = totalCliffs.sub(cliff).mul(5).div(2).add(700);
            // e.g. (new) amount = 1e19 * 1700 / 500 =  34e18;
            // e.g. (new) amount = 1e19 * 1325 / 500 =  26.5e18;
            // e.g. (new) amount = 1e19 * 950 / 500  =  19e17;
            amount = _amount.mul(reduction).div(totalCliffs);
            // e.g. amtTillMax = 5e25 - 1e25 = 4e25
            uint256 amtTillMax = maxSupply.sub(emissionsMinted);
            if (amount > amtTillMax) {
                amount = amtTillMax;
            }
        }
    }

    /**
     * @notice
     *  Provide an accurate estimate for the total amount of assets
     *  (principle + return) that this Strategy is currently managing,
     *  denominated in terms of `want` tokens.
     *
     *  This total should be "realizable" e.g. the total value that could
     *  *actually* be obtained from this Strategy if it were to divest its
     *  entire position based on current on-chain conditions.
     * @dev
     *  Care must be taken in using this function, since it relies on external
     *  systems, which could be manipulated by the attacker to give an inflated
     *  (or reduced) value produced by this function, based on current on-chain
     *  conditions (e.g. this function is possible to influence through
     *  flashloan attacks, oracle manipulations, or other DeFi attack
     *  mechanisms).
     *
     *  It is up to governance to use this function to correctly order this
     *  Strategy relative to its peers in the withdrawal queue to minimize
     *  losses for the Vault based on sudden withdrawals. This value should be
     *  higher than the total debt of the Strategy and higher than its expected
     *  value to be "safe".
     * @return _wants The estimated total assets in this Strategy.
     */
    function estimatedTotalAssets() public view override returns (uint256 _wants) {
        // WETH + BPT (B-rETH-Stable) + auraBPT (auraB-rETH-Stable) + AURA (rewards) + BAL (rewards)
        // should be converted to WETH using balancer
        // calcOutGivenIn
        _wants = balanceOfWant();

        uint256 bptTokens = balanceOfUnstakedBpt() + auraBptToBpt(balanceOfAuraBpt());
        _wants += bptsToWant(bptTokens);

        uint256 balTokens = balRewards();
        if(balTokens > 0){
            _wants += balToWeth(balTokens);
        }

        uint256 auraTokens = auraRewards(balTokens);
        if(auraTokens > 0){
            _wants += auraToWeth(auraTokens);
        }

        return _wants;
    }

    function auraToWeth(uint256 auraTokens) public view returns (uint256) {
        uint unscaled = auraTokens.mul(getAuraPrice()).div(1e18);
        return _scaleDecimals(unscaled, ERC20(address(auraToken)), ERC20(address(want)));
    }

    function balToWeth(uint256 balTokens) public view returns (uint256) {
        uint unscaled = balTokens.mul(getBalPrice()).div(1e18);
        return _scaleDecimals(unscaled, ERC20(address(balToken)), ERC20(address(want)));
    }

    function getBalPrice() public view returns (uint256 price) {
        address priceOracle = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;
        IBalancerPriceOracle.OracleAverageQuery[] memory queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        // weighted average price for last 30 minutes
        queries[0] = IBalancerPriceOracle.OracleAverageQuery(IBalancerPriceOracle.Variable.PAIR_PRICE, 1800, 0);
        uint256[] memory results = IBalancerPriceOracle(priceOracle).getTimeWeightedAverage(queries);
        price = 1e36 / results[0];
    }

    function getAuraPrice() public view returns (uint256 price) {
        address priceOracle = 0xc29562b045D80fD77c69Bec09541F5c16fe20d9d;
        IBalancerPriceOracle.OracleAverageQuery[] memory queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        // weighted average price for last 30 minutes
        queries[0] = IBalancerPriceOracle.OracleAverageQuery(IBalancerPriceOracle.Variable.PAIR_PRICE, 1800, 0);
        uint256[] memory results = IBalancerPriceOracle(priceOracle).getTimeWeightedAverage(queries);
        price = results[0];
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
        uint256 _totalAssets = estimatedTotalAssets();
        uint256 _totalDebt = vault.strategies(address(this)).totalDebt;

        if(_totalAssets >= _totalDebt) {
            _profit = _totalAssets - _totalDebt;
            _loss = 0;
        } else {
            _profit = 0;
            _loss = _totalDebt - _totalAssets;
        }

        withdrawSome(_debtOutstanding + _profit);

        uint256 _liquidWant = want.balanceOf(address(this));

        // enough to pay profit (partial or full) only
        if(_liquidWant <= _profit) {
            _profit = _liquidWant;
            _debtPayment = 0;
        // enough to pay for all profit and _debtOutstanding (partial or full)
        } else {
            _debtPayment = Math.min(_liquidWant - _profit, _debtOutstanding);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)

        IAuraBooster(auraBooster).earmarkRewards(15);
        uint256 balBal = IERC20(balToken).balanceOf(address(this));
        uint256 auraBal = IERC20(auraToken).balanceOf(address(this));
        if(balBal > 0 && auraBal > 0){
            _sellBalAndAura(balBal, auraBal);
        }

        uint256 _wethBal = want.balanceOf(address(this));

        if(_wethBal > _debtOutstanding){
            // 1. Farm WETH in Balancer rETH-WETH pool

            // @TODO Calculate slippage to prevent frontrun https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html#maxamountsin
            uint256 _excessWeth = _wethBal - _debtOutstanding;
            
            address[] memory _assets = new address[](2);
            _assets[0] = address(rETH);
            _assets[1] = address(want);

            uint256[] memory _maxAmountsIn = new uint256[](2);
            _maxAmountsIn[0] = 0;
            _maxAmountsIn[1] = _excessWeth;

            uint256[] memory _amountsIn = new uint256[](2);
            _amountsIn[0] = 0;
            _amountsIn[1] = _excessWeth; 
            uint256 _minimumBPT = 1; // @TODO Calculate slippage to prevent frontrun https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html#maxamountsin            

            bytes memory _userData = abi.encode(IBalancerV2Vault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, _amountsIn, _minimumBPT);
            // console.log("userdata", address(vault));
            // console.logBytes( _userData);
            IBalancerV2Vault.JoinPoolRequest memory _request;
            _request = IBalancerV2Vault.JoinPoolRequest(
                _assets,
                _maxAmountsIn,
                _userData,
                false
            );
            
            // https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html
            // https://medium.com/coinmonks/dissecting-the-balancer-v2-protocol-part-1-9a3432687834
            // Error codes https://docs.balancer.fi/reference/contracts/error-codes.html#pools
            balancerVault.joinPool(
                poolId, // poolId
                address(this), // sender
                address(this), // recipient
                _request
            );

            // 2. Farm WETH in Balancer rETH-WETH pool
            bool auraSuccess = IAuraDeposit(auraBooster).deposit(
                15, // PID
                IBalancerPool(bRethStable).balanceOf(address(this)), // @TODO deposit only what we got from current balancer joinPool
                true // stake
            );
            // console.log("auraSuccess", auraSuccess);
        }
    }

    function _sellBalAndAura(uint256 _balAmount, uint256 _auraAmount)
        internal
    {
        IBalancerV2Vault.BatchSwapStep[] memory swaps = new IBalancerV2Vault.BatchSwapStep[](2);

        // bal to weth
        swaps[0] = IBalancerV2Vault.BatchSwapStep({
            poolId: balEthPoolId,
            assetInIndex: 0,
            assetOutIndex: 2,
            amount: _balAmount,
            userData: abi.encode(0)
        });

        // aura to Weth
        swaps[1] = IBalancerV2Vault.BatchSwapStep({
            poolId: auraEthPoolId,
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: _auraAmount,
            userData: abi.encode(0)
        });

        address[] memory assets = new address[](3);
        assets[0] = balToken;
        assets[1] = auraToken;
        assets[2] = address(want);
        
        int[] memory limits = new int[](3);
        limits[0] = int(_balAmount);
        limits[1] = int(_auraAmount);
        
        balancerVault.batchSwap(
            IBalancerV2Vault.SwapKind.GIVEN_IN, 
            swaps, 
            assets, 
            getFundManagement(), 
            limits, 
            block.timestamp
        );
    }

    function withdrawSome(uint256 _amountNeeded) internal {
        // @TODO better use queryExit
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#minamountsout
        uint256 wethToBpt = wantToBpts(_amountNeeded);
        uint256 bptToUnstake = Math.min(wethToBpt, IERC20(auraBRethStable).balanceOf(address(this)));

        if(bptToUnstake > 0){
            IConvexRewards(auraBRethStable).withdrawAndUnwrap(bptToUnstake, true);

            _sellBalAndAura(
                IERC20(balToken).balanceOf(address(this)),
                IERC20(auraToken).balanceOf(address(this))
            );

            // exit entire position for single token. Could revert due to single exit limit enforced by balancer
            address[] memory _assets = new address[](2);
            _assets[0] = address(rETH);
            _assets[1] = address(want);
            
            uint256[] memory _minAmountsOut = new uint256[](2);
            _minAmountsOut[0] = 0;
            _minAmountsOut[1] = _amountNeeded * slippage / 10000;
            bytes memory userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptToUnstake, 1);
            // @TODO set _minAmountsOut
            IBalancerV2Vault.ExitPoolRequest memory request = IBalancerV2Vault.ExitPoolRequest(_assets, _minAmountsOut, userData, false);
            balancerVault.exitPool(poolId, address(this), payable(address(this)), request);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        // console.log("wETH tokens", want.balanceOf(address(this)));
        // console.log("Start liquidate positions:", _amountNeeded);
        uint256 _wethBal = want.balanceOf(address(this));
        if(_wethBal >= _amountNeeded){
            return (_amountNeeded, 0);
        }

        // console.log("Earmark rewards");
        IAuraBooster(auraBooster).earmarkRewards(15);

        // @TODO withdraw only rewards if possible
        // to safe position
        // console.log("Withdraw wETH", _amountNeeded);
        withdrawSome(_amountNeeded);

        _wethBal = want.balanceOf(address(this));
        // console.log("wETH tokens", want.balanceOf(address(this)));

        if (_amountNeeded > _wethBal) {
            _liquidatedAmount = _wethBal;
            _loss = _amountNeeded - _wethBal;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // @TODO sell using BatchSwap
        // https://etherscan.io/address/0x33e1086881f3664406bba42dcae038c5cd26f184#code#L2099

        // console.log("Start liquidating all positions");

        // console.log("\nauraBrETH tokens:", IERC20(auraBRethStable).balanceOf(address(this)));
        // console.log("brEth tokens:", IERC20(bRethStable).balanceOf(address(this)));
        // console.log("AURA tokens:", IERC20(auraToken).balanceOf(address(this)));
        // console.log("BAL tokens:", IERC20(balToken).balanceOf(address(this)));
        // console.log("want tokens:", want.balanceOf(address(this)));

        // // 1. Unwrap LP tokens
        // console.log("Unwrap auraBrEthStable to BrEthStable");
        IConvexRewards auraPool = IConvexRewards(auraBRethStable);
        auraPool.withdrawAndUnwrap(auraPool.balanceOf(address(this)), true);

        // console.log("\nauraBrETH tokens:", IERC20(auraBRethStable).balanceOf(address(this)));
        // console.log("brEth tokens:", IERC20(bRethStable).balanceOf(address(this)));
        // console.log("AURA tokens:", IERC20(auraToken).balanceOf(address(this)));
        // console.log("BAL tokens:", IERC20(balToken).balanceOf(address(this)));
        // console.log("want tokens:", want.balanceOf(address(this)));

        // console.log("\nExit from pool. Send BrEthStable and get wETH");
        // 2. Remove liquidity from pool
        // exit entire position for single token. Could revert due to single exit limit enforced by balancer
        address[] memory _assets = new address[](2);
        _assets[0] = address(rETH);
        _assets[1] = address(want);
        
        // @TODO set _minAmountsOut
        uint256[] memory _minAmountsOut = new uint256[](2);
        bytes memory userData = abi.encode(
            IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, 
            IERC20(bRethStable).balanceOf(address(this)), 
            1
        );
        IBalancerV2Vault.ExitPoolRequest memory request = IBalancerV2Vault.ExitPoolRequest(_assets, _minAmountsOut, userData, false);
        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);    

        // 3. Sell rewards
        _sellBalAndAura(
            IERC20(balToken).balanceOf(address(this)),
            IERC20(auraToken).balanceOf(address(this))
        );

        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    // solhint-disable-next-line no-empty-blocks
    function prepareMigration(address _newStrategy) internal override {
        // auraBRethStable do not allow to transfer so we just unwrap it
        IConvexRewards auraPool = IConvexRewards(auraBRethStable);
        auraPool.withdrawAndUnwrap(auraPool.balanceOf(address(this)), true);

        uint256 auraBal = IERC20(auraToken).balanceOf(address(this));
        if (auraBal > 0) {
            IERC20(auraToken).safeTransfer(_newStrategy, auraBal);
        } 
        uint256 balancerBal = IERC20(balToken).balanceOf(address(this));
        if (balancerBal > 0) {
            IERC20(balToken).safeTransfer(_newStrategy, balancerBal);
        } 
        uint256 bptBal = IERC20(bRethStable).balanceOf(address(this));
        if (bptBal > 0) {
            IERC20(bRethStable).safeTransfer(_newStrategy, bptBal);
        } 
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](4);
        protected[0] = bRethStable;
        protected[1] = auraBRethStable;
        protected[2] = balToken;
        protected[3] = auraToken;
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _amtInWei;
    }

    function getFundManagement() 
        internal 
        view 
        returns (IBalancerV2Vault.FundManagement memory fundManagement) 
    {
        fundManagement = IBalancerV2Vault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        }); 
    }


}
