// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../interfaces/ILocusDataFeed.sol";
import "../interfaces/ILocusDataFeedUser.sol";

contract LocusDataFeed is ILocusDataFeed, AccessControl {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;
    
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    mapping(address => EnumerableSet.Bytes32Set) internal _addressToTopicIds;
    EnumerableMap.Bytes32ToBytes32Map internal _dataFeed;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(UPDATER_ROLE, _msgSender());
    }

    function getDomain(
        address entity
    ) external view override returns (bytes32[] memory keys) {
        uint256 domainLength = _addressToTopicIds[entity].length();
        keys = new bytes32[](domainLength);
        for (uint256 i; i < domainLength; i++) {
            keys[i] = _addressToTopicIds[entity].at(i);
        }
    }

    function getValue(uint256 topicNumber) external view override returns (bytes32) {
        return _dataFeed.get(_addressToTopicIds[_msgSender()].at(topicNumber));
    }

    function setValue(uint256 topicNumber, bytes32 value) external override {
        _dataFeed.set(_addressToTopicIds[_msgSender()].at(topicNumber), value);
    }

    function getValueFrom(address entity, uint256 topicNumber) public view override returns (bytes32) {
        return _dataFeed.get(_addressToTopicIds[entity].at(topicNumber));
    }

    function updateFeed(address entity) external override {
        uint256 topicsAmount = getTopicsAmount(entity);
        for (uint256 i; i < topicsAmount; i++) {
            _dataFeed.set(
                _addressToTopicIds[entity].at(i), 
                ILocusDataFeedUser(entity).updateFeedRequested(i)
            );
        }
    }

    function getTopicsAmount(address entity) public view returns (uint256) {
        return _addressToTopicIds[entity].length();
    }

    function parseUint256FromFeed(address entity, uint256 topicNumber) public view returns (uint256) {
        return uint256(getValueFrom(entity, topicNumber));
    }

    function parseAddressFromFeed(address entity, uint256 topicNumber) public view returns (address) {
        return address(SafeCast.toUint160(parseUint256FromFeed(entity, topicNumber)));
    }

    function setFeed(
        uint256 maxTopics // the topics would be created and numbered from 0 to maxTopics;
    ) external override {
        address entity = _msgSender();
        for (uint256 i; i < maxTopics; i++) {
            bytes32 key = keccak256(abi.encodePacked(entity, i));
            _addressToTopicIds[entity].add(key);
            _dataFeed.set(key, bytes32(0));
        }
    }
}
