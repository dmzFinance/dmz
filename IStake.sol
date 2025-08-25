// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStake {
    // Define the structure for a stake
    enum Role {
        Admin,
        Lender,
        Borrower
    }
    enum UnstakeRequestStatus {
        Pending,
        Approved,
        Rejected
    }

    struct UnstakeRequest {
        address initiator;
        address approver;
        address lenderAddress;
        address borrowerAddress;
        address tokenAddress;
        uint256 initiateTime;
        uint256 approveTime;
        uint256 borrowerAmount;
        uint256 lenderAmount;
        UnstakeRequestStatus status;
    }
    struct Balance {
        uint256 available;
        uint256 freezed;
    }

    // Events
    event Staked(address borrower, uint256 amount, address tokenAddress, address lenderAddress);
    event InitiatedUnstake(
        bytes32 requestID,
        address initiator,
        uint256 borrowerAmount,
        uint256 lenderAmount,
        address tokenAddress,
        address lenderAddress,
        address borrowerAddress
    );
    event ApprovedUnstake(
        bytes32 requestID,
        address approver,
        uint256 borrowerAmount,
        uint256 lenderAmount,
        address tokenAddress,
        address lenderAddress,
        address borrowerAddress
    );
    event RejectedUnstake(
        bytes32 requestID,
        address approver,
        uint256 borrowerAmount,
        uint256 lenderAmount,
        address tokenAddress,
        address lenderAddress,
        address borrowerAddress
    );
    event TokenRegistered(address tokenAddress);
    event TokenUnregistered(address tokenAddress);



    // Functions
    function stake(uint256 amount, address tokenAddress, address lenderAddress) external;
    function unstake(address tokenAddress, address lenderAddress, address borrowerAddress, uint256 borrowerAmount, uint256 lenderAmount) external returns(bytes32);
    function approveUnstake(bytes32 requestID) external;
    function rejectUnstake(bytes32 requestID) external;
    function addLender(address lender) external;
    function deleteLender(address lender) external;
    function addAdmin(address admin) external;
    function deleteAdmin(address admin) external;
    function isAdmin(address addr) external view returns (bool);
    function isLender(address addr) external view returns (bool);
    function registerToken(address tokenAddress) external;
    function unregisterToken(address tokenAddress) external;
    function isTokenRegistered(address tokenAddress) external view returns (bool);
    function getBalance(address tokenAddress, address lenderAddress, address borrowerAddress) external view returns (uint256, uint256);
    function getUnstake(bytes32 requestID) external view returns (address initiator, address approver, address lenderAddress, address borrowerAddress, address tokenAddress, uint256 initiateTime, uint256 approveTime, uint256 borrowerAmount, uint256 lenderAmount, UnstakeRequestStatus status);
}
