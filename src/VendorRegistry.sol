//SPDX-License-Identifier: UNLICENSED 

pragma solidity ^0.8.0;

import {Timelock} from "src/Timelock.sol" ;

contract vendorRegistry{

    Timelock timelock;
    address proposer;

    constructor(address _timelock, address Proposer){
        timelock = Timelock(_timelock);
        proposer = Proposer;
    }

    modifier onlyTimelock() {
        require(msg.sender == address(timelock), "Only timelock can call this function");
        _;
    }

    modifier onlyProposer(){
        require(msg.sender == proposer, "You do not have access");
        _;
    }

    struct Vendor{
        string vendorName ;
        string vendorAddress;
        uint256 addressPostalCode;
        uint256 contactNumber;
    }

    event vendorAdded(string vendorName, address vendorAddress);

    mapping(address => Vendor) internal vendors;
    mapping(address => bool) internal vendorExists;
    mapping(address => bool) internal vendorPending;

    //maybe we can make this memory into calldata
    function addDetails(address vendorAddr, string memory _addr, uint256 _postal, uint256 _contact) public onlyProposer {
        require(vendorExists[vendorAddr], "No such vendor exists");

        vendors[vendorAddr].vendorAddress = _addr;
        vendors[vendorAddr].addressPostalCode = _postal;
        vendors[vendorAddr].contactNumber = _contact;
    }

    function isRegistered(address vendorAddr) external view returns (bool){
        return vendorExists[vendorAddr];
    }

    function execute(address vendorAddr, string calldata vendorName) external onlyTimelock {
        require(!vendorExists[vendorAddr], "Vendor already registered");
        vendorExists[vendorAddr] = true;
        vendors[vendorAddr].vendorName = vendorName;
        vendorPending[vendorAddr] = false;

        emit vendorAdded(vendorName, vendorAddr);
    }

    function register(address vendorAddr, string memory vendorName) public onlyProposer{
        require(!vendorExists[vendorAddr] && !vendorPending[vendorAddr], "This vendor already exists cannot register again");
        bytes memory encodedData = abi.encode(
            //in solidity, using this give the contract instance not contract name
            address(this), 
            abi.encodeWithSelector(
                vendorRegistry.execute.selector,
                vendorAddr,
                vendorName
            )
        );
        vendorPending[vendorAddr] = true;
        timelock.schedule(encodedData, 48 hours);
    }

    function cancelRegistration(address vendorAddr) public onlyProposer {
    require(vendorPending[vendorAddr], "No pending registration");

    bytes memory encodedData = abi.encode(
        address(this),
        abi.encodeWithSelector(
            vendorRegistry.execute.selector,
            vendorAddr,
            vendors[vendorAddr].vendorName
        )
    );

    bytes32 operationId = timelock.getOpId(encodedData);

    timelock.cancel(operationId);

    vendorPending[vendorAddr] = false;
    }
}
