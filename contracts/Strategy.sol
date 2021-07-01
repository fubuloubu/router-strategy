// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {BaseWrapper, VaultAPI} from "@yearnvaults/contracts/BaseWrapper.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy, BaseWrapper {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    constructor(
        address _vault,
        address _token,
        address _registry
    ) public BaseStrategy(_vault) BaseWrapper(_token, _registry) {}

    function name() external view override returns (string memory) {
        return "RouterStrategy";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return
            token.balanceOf(address(this)).add(
                totalVaultBalance(address(this))
            );
    }

    function delegatedAssets() external view override returns (uint256) {
        // All assets are delegated
        return estimatedTotalAssets();
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
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;
        uint256 totalAssets = estimatedTotalAssets();

        if (totalAssets > totalDebt) {
            _profit = totalAssets.sub(totalDebt);
        }

        _withdraw(
            address(this),
            address(this),
            _debtOutstanding.add(_profit),
            true
        );
        uint256 withdrawn = token.balanceOf(address(this));

        if (withdrawn < _debtOutstanding) {
            _profit = 0;
            _loss = _debtOutstanding.sub(withdrawn);
            _debtPayment = withdrawn;
        } else {
            _debtPayment = _debtOutstanding;
            _profit = withdrawn.sub(_debtOutstanding);
            // No loss
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // NOTE: Only deposit what's not outstanding
        uint256 totalAssets =
            want.balanceOf(address(this)).sub(_debtOutstanding);
        _deposit(address(this), address(this), totalAssets, false);
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        uint256 totalAssets = want.balanceOf(address(this));
        if (totalAssets >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        if (totalVaultBalance(address(this)) < _amountNeeded.sub(totalAssets)) {
            _withdraw(address(this), address(this), uint256(-1), true); // Withdraw everything
        } else {
            _withdraw(
                address(this),
                address(this),
                _amountNeeded.sub(totalAssets),
                true
            );
        }

        totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _withdraw(address(this), address(this), uint256(-1), true); // Withdraw everything
        return want.balanceOf(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        VaultAPI[] memory vaults = allVaults();
        // Transfer all vault shares to new strategy (don't migrate funds)
        for (uint256 i; i < vaults.length; i++) {
            uint256 balance = vaults[i].balanceOf(address(this));
            if (balance > 0) {
                vaults[i].transfer(_newStrategy, balance);
            }
        }
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        VaultAPI[] memory vaults = allVaults();
        address[] memory _protectedTokens;
        for (uint256 i; i < vaults.length; i++) {
            _protectedTokens[i] = address(vaults[i]);
        }
        return _protectedTokens;
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
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
