//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

contract Timelock{

    uint256 public constant MIN_DELAY = 24 hours ;

    //Use .env file to store the addresses of the Roles
    enum OperationState {Unset, Waiting, Ready, Done} 
    OperationState constant defaultState = OperationState.Unset;

    address proposer;
    address executor;
    address cancellor;


    uint8 constant PROPOSER_ROLE = 1 << 0;
    uint8 constant CANCELLOR_ROLE = 1 << 1;
    uint8 constant EXECUTOR_ROLE = 1 << 2;

    mapping(address => uint8) authRoles;

    constructor(
    address Proposer,
    address Cancellor,
    address Executor
    ) {
        proposer = Proposer;
        authRoles[Proposer] |= PROPOSER_ROLE;

        cancellor = Cancellor;
        authRoles[Cancellor] |= CANCELLOR_ROLE;

        executor = Executor;
        authRoles[Executor] |= EXECUTOR_ROLE;
    }

    error stateDone (string message);

    //Cannot execute a state changing assignment inside the contract body
    //authRole[proposer].name = 'proposer';


    event stateReady( OperationState _state );
    event scheduled (bytes32 operationId , uint256 _eta);

    // from operationID to Which state the operation is in the queue
    mapping( bytes32 => bytes) internal tEncodedData ;
    mapping( bytes32 => OperationState ) internal queue ;
    mapping(bytes32 => uint256 ) internal eta ;

    //string needs to be compared by their hashed
    //require(authRole[msg.sender].name == "proposer", "Not authorised to run this");
        

    modifier onlyProposer() {
        require(
            (authRoles[msg.sender] & PROPOSER_ROLE) != 0,
            "Not authorised to run this"
        );
        _;
    }

    modifier onlyCancellor() {
        require(
            (authRoles[msg.sender] & CANCELLOR_ROLE) != 0,
            "Not authorised to run this"
        );
        _;
    }

    modifier onlyExecutor() {
        require(
            (authRoles[msg.sender] & EXECUTOR_ROLE) != 0,
            "Not authorised to run this"
        );
        _;
    }

    


    function execute(bytes32 operationId) public onlyExecutor {
        require ( checkState(operationId) == OperationState.Ready, "Operation not in Ready, please checkState to ensure state of operation") ;
        queue[operationId] = OperationState.Done;
        (address target, bytes memory _data) = abi.decode(tEncodedData[operationId],( address, bytes));
        require(target.code.length > 0, "Target is not a contract");
        (bool success, ) = target.call(_data);
        require(success, "Transaction failed");
    }

    //logic fully built
    function checkState(bytes32 operationId) public view returns(OperationState _state){
        //require(queue[operationId], "Operation not scheduled yet !");
        //by deafult all OperationStates will be Unset
        //if eta < block.timestamp no way it is done
        if(queue[operationId] != OperationState.Unset){
            if(block.timestamp < eta[operationId]){
                return OperationState.Waiting;
            }
            else if (block.timestamp >= eta[operationId]){
                if(queue[operationId] != OperationState.Done){
                    return OperationState.Ready;
                }
                else{
                    return OperationState.Done;
                }
            }
        }
        //replaces the require
        else{
            return OperationState.Unset;
        }
    }

    //logic fully built
    function cancel(bytes32 operationId) public onlyCancellor {
        // We dont do anything for if it is unset as it cannot be cancelled since it hasn't yet been scheduled
        OperationState _state = checkState(operationId);
        if(_state != OperationState.Unset){
            if(_state != OperationState.Done){
                queue[operationId] = OperationState.Unset;
            }
            else{
                revert stateDone ({
                    message : "Operation already executed, cannot cancel anymore"
                });
            }
        }
    }

    //completed function
    function getOpId(bytes memory encodedData) public pure returns (bytes32 result){
        result = keccak256(abi.encode(encodedData, "salt"));
        return result;
    }

    //logic built completely
    function schedule(bytes memory encodedData, uint _delay) public onlyProposer returns (uint256 _eta, bytes32 opId){

        bytes32 operationId = getOpId(encodedData);
        require (queue[operationId] == defaultState, "Operation already Scheduled");
        tEncodedData[operationId] = encodedData;
        queue[operationId] = OperationState.Waiting;
        if(_delay < MIN_DELAY){
            _eta = block.timestamp + MIN_DELAY ;
            eta[operationId] = _eta;
        }
        else{
            _eta = block.timestamp + _delay ;
            eta[operationId] = _eta;
        }
        opId = operationId;
        emit scheduled(operationId,_eta);
    }

}