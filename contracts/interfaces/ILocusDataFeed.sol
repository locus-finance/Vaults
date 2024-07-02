// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILocusDataFeed {
    function getDomain(
        address entity
    ) external view returns (bytes32[] memory keys);

    function getValue(uint256 topicNumber) external view returns (bytes32);

    function setValue(uint256 topicNumber, bytes32 value) external;

    function updateFeed(address entity) external;

    function setFeed(
        uint256 maxTopics // the topics would be created and numbered from 0 to maxTopics;
    ) external;

    function getValueFrom(
        address entity,
        uint256 topicNumber
    ) external view returns (bytes32);

    function getTopicsAmount(address entity) external view returns (uint256);

    function parseUint256FromFeed(
        address entity,
        uint256 topicNumber
    ) external view returns (uint256);

    function parseAddressFromFeed(
        address entity,
        uint256 topicNumber
    ) external view returns (address);
}
