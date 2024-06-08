// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";

interface YearnVaultV3Strategy {
    function report() external;
    function keeper() external returns (address);
}

abstract contract YearnVaultV3 is ERC4626 {
    enum Role {
        ADD_STRATEGY_MANAGER, // Can add strategies to the vault.
        REVOKE_STRATEGY_MANAGER, // Can remove strategies from the vault.
        FORCE_REVOKE_MANAGER, // Can force remove a strategy causing a loss.
        ACCOUNTANT_MANAGER, // Can set the accountant that assess fees.
        QUEUE_MANAGER, // Can set the default withdrawal queue.
        REPORTING_MANAGER, // Calls report for strategies.
        DEBT_MANAGER, // Adds and removes debt from strategies.
        MAX_DEBT_MANAGER, // Can set the max debt for a strategy.
        DEPOSIT_LIMIT_MANAGER, // Sets deposit limit and module for the vault.
        WITHDRAW_LIMIT_MANAGER, // Sets the withdraw limit module.
        MINIMUM_IDLE_MANAGER, // Sets the minimum total idle the vault should keep.
        PROFIT_UNLOCK_MANAGER, // Sets the profit_max_unlock_time.
        DEBT_PURCHASER, // Can purchase bad debt from the vault.
        EMERGENCY_MANAGER // Can shutdown vault in an emergency.

    }

    function default_queue(uint256 i) external view virtual returns (YearnVaultV3Strategy);
    function get_default_queue() external view virtual returns (YearnVaultV3Strategy[] memory);
    function process_report(YearnVaultV3Strategy strategy) external virtual;
}
