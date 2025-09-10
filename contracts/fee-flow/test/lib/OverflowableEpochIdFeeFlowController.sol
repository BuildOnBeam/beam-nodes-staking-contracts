// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "../../FeeFlowControllerNative.sol";

contract OverflowableEpochIdFeeFlowController is FeeFlowControllerNative {
    constructor(
        uint256 initPrice,
        address paymentToken_,
        address paymentReceiver_,
        uint256 epochPeriod_,
        uint256 priceMultiplier_,
        uint256 minInitPrice_
    )
        FeeFlowControllerNative(
            initPrice,
            paymentToken_,
            paymentReceiver_,
            epochPeriod_,
            priceMultiplier_,
            minInitPrice_
        )
    {}

    function setEpochId(
        uint16 epochId
    ) public {
        slot0.epochId = epochId;
    }
}
