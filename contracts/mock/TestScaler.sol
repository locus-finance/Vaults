import "../strategies/RocketAuraStrategy.sol";
import "../utils/AuraMath.sol";

contract TestScaler is RocketAuraStrategy {
    constructor(address _vault) RocketAuraStrategy(_vault) {}

    function scaleDecimals(
        uint _amount,
        ERC20 _fromToken,
        ERC20 _toToken
    ) public view returns (uint _scaled) {
        return Utils.scaleDecimals(_amount, _fromToken, _toToken);
    }
}
