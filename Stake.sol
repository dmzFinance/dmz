// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IStake.sol";

contract DMZStake is IStake, Ownable {
    using SafeERC20 for IERC20;
    mapping(bytes32 => Balance) private _balances;
    mapping(bytes32 => UnstakeRequest) public unstakeRequests;
    mapping(address => bool) private _lenders;
    mapping(address => bool) private _admins;
    uint256 private transactionCounter;
    mapping(address => bool) public tokenRegistered;


    constructor(address initialOwner) Ownable(initialOwner) {
    }
    function registerToken(address tokenAddress) public onlyOwner {
        require(tokenAddress != address(0), "Token address cannot be zero");
        require(!tokenRegistered[tokenAddress], "Token already registered");
        tokenRegistered[tokenAddress] = true;
        emit TokenRegistered(tokenAddress);
    }

    function unregisterToken(address tokenAddress) public onlyOwner {
        require(tokenRegistered[tokenAddress], "Token not registered");
        tokenRegistered[tokenAddress] = false;
        emit TokenUnregistered(tokenAddress);
    }

    function isTokenRegistered(address tokenAddress) public view returns (bool) {
        return tokenRegistered[tokenAddress];
    }

    function _generateBalanceKey(address lender, address borrower, address tokenContract) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(lender, borrower, tokenContract));
    }
    function _generateRequestID() internal returns (bytes32) {
        transactionCounter++;
        return keccak256(abi.encodePacked(transactionCounter));
    }

    function stake(uint256 amount, address tokenAddress, address lenderAddress) external  {
        require(amount > 0, "Amount must be greater than 0");
        require(isTokenRegistered(tokenAddress), "Token address must be registered to perform this action");
        require(_lenders[lenderAddress], "Lender is not registered");

        bytes32 key =  _generateBalanceKey(lenderAddress, msg.sender, tokenAddress);
        if (_balances[key].available > 0 || _balances[key].freezed > 0) {
            _balances[key].available += amount;
        } else {
            _balances[key] = Balance(amount, 0);
        }
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount, tokenAddress, lenderAddress);
    }


    function unstake(address tokenAddress, address lenderAddress, address borrowerAddress, uint256 borrowerAmount, uint256 lenderAmount) external returns (bytes32) {
        bytes32 balanceKey =  _generateBalanceKey(lenderAddress, borrowerAddress, tokenAddress);
        Balance storage balance = _balances[balanceKey];
        require(msg.sender == borrowerAddress || msg.sender == lenderAddress, "Only borrower or lender can initiate unstake");
        require(balance.available >= borrowerAmount + lenderAmount, "Available balance is not enough");

        balance.available -= (borrowerAmount + lenderAmount);
        balance.freezed += (borrowerAmount + lenderAmount);

        bytes32 requestId = _generateRequestID();
        unstakeRequests[requestId] = UnstakeRequest({
            initiator: msg.sender,
            approver: address(0),
            lenderAddress: lenderAddress,
            borrowerAddress: borrowerAddress,
            tokenAddress: tokenAddress,
            initiateTime: block.timestamp,
            approveTime: 0,
            borrowerAmount: borrowerAmount,
            lenderAmount: lenderAmount,
            status: UnstakeRequestStatus.Pending
        });

        emit InitiatedUnstake(requestId, msg.sender, borrowerAmount, lenderAmount, tokenAddress, lenderAddress, borrowerAddress);
        return requestId;
    }

    function approveUnstake(bytes32 requestId) external {
        UnstakeRequest storage request = unstakeRequests[requestId];
        require(request.status == UnstakeRequestStatus.Pending, "Request must be in pending status");
        require(msg.sender != request.initiator, "Initiator cannot approve the request");
        require(
            msg.sender == request.lenderAddress || 
            msg.sender == request.borrowerAddress || 
            _admins[msg.sender], 
            "Approver must be lender, borrower, or an admin and not the initiator"
        );

        bytes32 balanceKey =  _generateBalanceKey(request.lenderAddress, request.borrowerAddress, request.tokenAddress);
        Balance storage balance = _balances[balanceKey];

        require(balance.freezed >= (request.borrowerAmount + request.lenderAmount), "Freezed balance is not enough");

        balance.freezed -= (request.borrowerAmount + request.lenderAmount);

        request.status = UnstakeRequestStatus.Approved;
        request.approver = msg.sender;
        request.approveTime = block.timestamp;

        IERC20 token = IERC20(request.tokenAddress);
        if(request.borrowerAmount > 0) {
            token.safeTransfer(request.borrowerAddress, request.borrowerAmount);
        }
        if(request.lenderAmount > 0) {
            token.safeTransfer(request.lenderAddress, request.lenderAmount);
        }

        emit ApprovedUnstake(requestId, msg.sender, request.borrowerAmount, request.lenderAmount, request.tokenAddress, request.lenderAddress, request.borrowerAddress);
    }
    function rejectUnstake(bytes32 requestId) external {
        UnstakeRequest storage request = unstakeRequests[requestId];
        require(request.status == UnstakeRequestStatus.Pending, "Request must be in pending status");
        require(
            msg.sender == request.lenderAddress || 
            msg.sender == request.borrowerAddress || 
            _admins[msg.sender], 
            "Only lender, borrower, or an admin can reject the request"
        );
        request.status = UnstakeRequestStatus.Rejected;
        request.approver = msg.sender;
        request.approveTime = block.timestamp;
        bytes32 balanceKey =  _generateBalanceKey(request.lenderAddress, request.borrowerAddress, request.tokenAddress);
        Balance storage balance = _balances[balanceKey];
        require(balance.freezed >= (request.borrowerAmount + request.lenderAmount), "Freezed balance does not match request amounts");

        balance.freezed -= (request.borrowerAmount + request.lenderAmount);
        balance.available += (request.borrowerAmount + request.lenderAmount);
        emit RejectedUnstake(requestId, msg.sender, request.borrowerAmount, request.lenderAmount, request.tokenAddress, request.lenderAddress, request.borrowerAddress);
    }


    function addLender(address lender) external onlyOwner {
        require(lender != address(0), "Invalid address");
        require(!_lenders[lender], "Already a lender");
        _lenders[lender] = true;
    }

    function deleteLender(address lender) external onlyOwner {
        require(_lenders[lender], "Not a lender");
        _lenders[lender] = false;
    }

    function addAdmin(address admin) external onlyOwner {
        require(admin != address(0), "Invalid address");
        require(!_admins[admin], "Already an admin");
        _admins[admin] = true;
    }

    function deleteAdmin(address admin) external onlyOwner {
        require(_admins[admin], "Not an admin");
        _admins[admin] = false;
    }

    function isAdmin(address addr) external view returns (bool) {
        return _admins[addr];
    }

    function isLender(address addr) external view returns (bool) {
        return _lenders[addr];
    }

    function getBalance(address tokenAddress, address lenderAddress, address borrowerAddress) external view returns (uint256, uint256) {
        bytes32 balanceKey =  _generateBalanceKey(lenderAddress, borrowerAddress, tokenAddress);
        Balance memory balance = _balances[balanceKey];
        return (balance.available, balance.freezed);
    }

    function getUnstake(bytes32 requestId) external view returns (address initiator, address approver, address lenderAddress, address borrowerAddress, address tokenAddress, uint256 initiateTime, uint256 approveTime, uint256 borrowerAmount, uint256 lenderAmount, UnstakeRequestStatus status) {
        UnstakeRequest storage request = unstakeRequests[requestId];
        return (
            request.initiator,
            request.approver,
            request.lenderAddress,
            request.borrowerAddress,
            request.tokenAddress,
            request.initiateTime,
            request.approveTime,
            request.borrowerAmount,
            request.lenderAmount,
            request.status
        );
    }
}
