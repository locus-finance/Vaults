// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILocusDataFeedUser {
    error OnlyLocusDataFeed();
    error UnknownTopicNumber(uint256 topicNumber);
    function updateFeedRequested(uint256 topicNumber) external returns(bytes32);
}