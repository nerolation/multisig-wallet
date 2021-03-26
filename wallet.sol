// SPDX-License-Identifier: MIT

pragma solidity =0.7.4;


contract OwnableWallet{
    address public owner;
    
    modifier onlyOwner{
        require(msg.sender == owner, "Sender not the owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function updateOwner(address _addr) public onlyOwner {
        owner = _addr;
    }
    
    function rescue(address payable _addr) public onlyOwner {
        (bool success,) =  _addr.call{value: address(this).balance}('');
        require(success, "Rescue failed");
    }
}

contract NotaryWallet is OwnableWallet{
    address [] public notaries;
    uint8 public revoltcounter; 
    mapping(address => bool) public isNotary;
    mapping(address => bool) public revolt;
    
    event NotaryAdded(address indexed addr);
    event NotaryRemoved(address indexed addr);

    modifier onlyNotary{
        require(isNotary[msg.sender] == true, "Not allowed");
        _;
    }
    
    function addNotary(address notary) public onlyOwner {
        require(isNotary[notary] == false, "Already Notary");
        isNotary[notary] = true;
        notaries.push(notary);
        emit NotaryAdded(notary);
    }
    
    function removeNotary(address notary) public onlyOwner {
        require(isNotary[notary] == true, "Not a Notary");
        isNotary[notary] = false;
        emit NotaryRemoved(notary);
    }
    
    function getNotaries() public view returns(address [] memory ){
        return notaries;
    }
    
    function mutiny() public onlyNotary {
        require(revolt[msg.sender] == false);
        require(notaries.length >= 2, "Not enough notaries");
        revolt[msg.sender] = true;
        revoltcounter += 1;
        if (revoltcounter >= notaries.length-1) {
            owner = msg.sender;
        }
    }
}

contract TimelockableWallet is OwnableWallet{
    uint public time;
    
    event TimelockAdded(uint indexed time);
    event TimelockRemoved(uint indexed time);
    
    modifier ifnotLocked {
        require(block.timestamp > time, "Timelocked");
        _;
    }
   
    function addTimeLock(uint ts) public onlyOwner {
        require(ts > block.timestamp);
        time = ts;
        emit TimelockAdded(time);
    }
    
    function removeTimeLock() public onlyOwner {
        require(time != 0);
        time = 0;
        emit TimelockRemoved(time);
    }
}

contract TokenManager is OwnableWallet{
    
    event TransferDone(address indexed cont, address indexed _addr, uint _val);
    
    function transferERC20(address _cont, address _addr, uint256 _val) public onlyOwner {
        (bool success, ) = _cont.call(abi.encodeWithSignature("transfer(address,uint256)", _addr, _val));
        require(success, "Transfer failed");
        emit TransferDone(_cont, _addr, _val);
    }
    
    function getERC20balance(address _cont, address _addr) public onlyOwner returns(bytes memory) {
        (bool success, bytes memory bal) = _cont.call(abi.encodeWithSignature("balanceOf(address)", _addr));
        require(success, "Call failed");
        return bal;
    }
}

contract MyWallet is OwnableWallet, NotaryWallet, TimelockableWallet, TokenManager{
    uint public walletbalance;
    
    event Execution(address indexed addr, bytes indexed data, uint indexed value);
    event Creation(address indexed addr, bytes indexed data, uint indexed value, uint reqconfs);
    event Sign(address indexed addr, uint indexed confs);
    event UndoSign(address indexed addr, uint indexed confs);
    
    mapping (address => mapping(uint => TX)) public notarysheet;
    mapping (address => mapping(address => bool)) confirmed;
    mapping (address => uint) notarycounter;
    
    struct TX {
        address destination;
        uint value;
        bytes data;
        uint confs;
        uint reqconf;
        bool executed;
    }

    constructor() OwnableWallet() {
        isNotary[msg.sender] = true;
        notaries.push(msg.sender);
    }
    
    receive() external payable {walletbalance += msg.value;}
    fallback() external payable {walletbalance += msg.value;}
    
    function deposit() external payable {walletbalance += msg.value;}
    
    function createTx(address _addr, uint _val, bytes memory _data, uint _reqconf) public onlyNotary {
        uint nc = notarycounter[msg.sender];
        notarysheet[msg.sender][nc] = TX(_addr,_val,_data,1,_reqconf,false);
        confirmed[msg.sender][msg.sender] = true;
        emit Creation(_addr,_data,_val,_reqconf);
    }
    
    function signTx(address _addr) public onlyNotary {
        require(confirmed[msg.sender][_addr] == false, "Already confirmed");
        uint nc = notarycounter[_addr];
        TX storage _tx = notarysheet[_addr][nc];
        _tx.confs += 1;
        confirmed[msg.sender][_addr] = true;
        emit Sign(_addr,_tx.confs);
    }
    
    function undosignTx(address _addr) public onlyNotary {
        require(confirmed[msg.sender][_addr] == true, "Not yet confirmed");
        uint nc = notarycounter[_addr];
        TX storage _tx = notarysheet[_addr][nc];
        _tx.confs -= 1;
        confirmed[msg.sender][_addr] = false;
        emit UndoSign(_addr,_tx.confs);
    }
    
    function executeTx(address payable _addr) public ifnotLocked {
        uint nc = notarycounter[_addr];
        TX storage _tx = notarysheet[_addr][nc];
        require(_tx.executed == false, "Tx already executed");
        require(_tx.destination != address(0), "Destination would be address(0)");
        require(_tx.value >= address(this).balance, "Insufficient contract balance");
        require(_tx.confs >= _tx.reqconf, "Not enough signatures");
        _tx.executed = true;
        notarycounter[_addr] += 1;
        walletbalance -= _tx.value;
        (bool success,) = _tx.destination.call{value: _tx.value}(_tx.data);
        require(success, "Transaction failed");
        emit Execution(_tx.destination, _tx.data, _tx.value);
    }
}
