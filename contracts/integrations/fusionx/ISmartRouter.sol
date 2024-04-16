// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import './ISelfPermit.sol';
import './IV2SwapRouter.sol';
import './IV3SwapRouter.sol';
import './IStableSwapRouter.sol';
import './IApproveAndCall.sol';
import './IMulticallExtended.sol';

/// @title Router token swapping functionality
interface ISmartRouter is IV2SwapRouter, IV3SwapRouter, IStableSwapRouter, IApproveAndCall, IMulticallExtended, ISelfPermit {

}
