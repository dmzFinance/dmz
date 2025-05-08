// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IdentityRegistry.sol";

contract MyToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit, AccessControl {
    address public identityRegistryAddress;
    enum CountryListType { Whitelist, Blacklist }
    CountryListType public countryListMode;
    bytes32[] public countryList;
    uint8 private _decimals;
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    enum RequestType { Mint, Burn }
    enum RequestStatus { Pending, Approved, Rejected }
    struct TokenRequest {
        RequestType requestType;
        address requester;
        address account;
        uint256 amount;
        RequestStatus status;
        uint256 requestedAt;
        uint256 finalizedAt;
    }
    bytes32 private _lastRequestID = 0x0;
    uint256 private _requestCounter = 0;
    mapping(bytes32 => TokenRequest) private _requests;
    mapping(address => bool) private _frozenAccounts;
    mapping(address => uint256) private _temporaryBalances;

    event MintRequestCreated(bytes32 requestID, address requester, address to, uint256 amount, uint256 timestamp);
    event BurnRequestCreated(bytes32 requestID, address requester, uint256 amount, uint256 timestamp);
    event RequestApproved(bytes32 requestID, uint256 timestamp, RequestType requestType);
    event RequestRejected(bytes32 requestID, uint256 timestamp, RequestType requestType);
    event AccountFrozen(address account);
    event AccountUnfrozen(address account);



    // Constructor
    constructor(
        string memory name, 
        string memory symbol,
        uint8 decimals_,
        address initialOwner,
        address _identityRegistryAddress,
        bytes32[] memory _countryList,
        CountryListType _countryListMode
    )
        ERC20(name, symbol)
        Ownable(initialOwner)
        ERC20Permit(name)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(FUND_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _decimals = decimals_;
        identityRegistryAddress = _identityRegistryAddress;
        countryList = _countryList;
        countryListMode = _countryListMode;
    }

    // Override decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // Pause and unpause functionality
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    
    function mintRequest(address to, uint256 amount) public returns (bytes32) {
        require(to != address(0), "Mint to the zero address");
        require(amount > 0, "Mint amount must be positive");
        _requestCounter++;

        bytes32 requestID = keccak256(abi.encodePacked(block.timestamp, msg.sender, _lastRequestID, uint8(RequestType.Mint), _requestCounter));
        _requests[requestID] = TokenRequest({
            requestType: RequestType.Mint,
            requester: msg.sender,
            account: to,
            amount: amount,
            status: RequestStatus.Pending,
            requestedAt: block.timestamp,
            finalizedAt: 0
        });
        _lastRequestID = requestID;
        emit MintRequestCreated(requestID, msg.sender, to, amount, block.timestamp);
        return requestID;
    }

    function burnRequest(uint256 amount) public returns (bytes32) {
        require(amount > 0, "Burn amount must be positive");
        
        _requestCounter++;
        bytes32 requestID = keccak256(abi.encodePacked(block.timestamp, msg.sender, _lastRequestID, uint8(RequestType.Burn), _requestCounter));
        _temporaryBalances[msg.sender] += amount;
        _requests[requestID] = TokenRequest({
            requestType: RequestType.Burn,
            requester: msg.sender,
            account: msg.sender,
            amount: amount,
            status: RequestStatus.Pending,
            requestedAt: block.timestamp,
            finalizedAt: 0
        });
        _lastRequestID = requestID;
        emit BurnRequestCreated(requestID, msg.sender, amount, block.timestamp);
        
        transfer(address(this), amount);
        
        return requestID;
    }


    function approveRequest(bytes32 requestID) public onlyRole(FUND_MANAGER_ROLE) {
        require(_requests[requestID].status == RequestStatus.Pending, "Request is not pending");
        TokenRequest storage request = _requests[requestID];
        
        if (request.requestType == RequestType.Mint) {
            _mint(request.account, request.amount);
        } else if (request.requestType == RequestType.Burn) {
            _burn(address(this), request.amount);
            _temporaryBalances[request.account] -= request.amount;
        }
        request.status = RequestStatus.Approved;
        request.finalizedAt = block.timestamp;
        emit RequestApproved(requestID, block.timestamp, request.requestType);
    }

    function rejectRequest(bytes32 requestID) public onlyRole(FUND_MANAGER_ROLE) {
        require(_requests[requestID].status == RequestStatus.Pending, "Request is not pending");
        TokenRequest storage request = _requests[requestID];

        if(request.requestType == RequestType.Burn) {
            _transfer(address(this), request.account, request.amount);
            _temporaryBalances[request.account] -= request.amount;
        }
        request.status = RequestStatus.Rejected;
        request.finalizedAt = block.timestamp;
        emit RequestRejected(requestID, block.timestamp, request.requestType);
    }

    function getRequest(bytes32 requestID) public view returns (TokenRequest memory) {
        return _requests[requestID];
    }

    // Admin forced transfer
    function forcedTransfer(address from, address to, uint256 amount) public onlyOwner {
        _transfer(from, to, amount);
    }
    function freezeAccount(address account) public onlyOwner {
        _frozenAccounts[account] = true;
        emit AccountFrozen(account);
    }

    function unfreezeAccount(address account) public onlyOwner {
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    // Whitelisting verification logic
    function _verifyWhitelisted(address account) internal view returns (bool) {
        if (identityRegistryAddress == address(0)) {
            return true;
        }
        IdentityRegistry registry = IdentityRegistry(identityRegistryAddress);
        (bool isWhitelisted, bytes32 country) = registry.verifyAddress(account);
        if (!isWhitelisted) {
            return false;
        }
        if (countryListMode == CountryListType.Whitelist) {
            return _isCountryInList(country);
        } else if (countryListMode == CountryListType.Blacklist) {
            return !_isCountryInList(country);
        }
        return true;
    }

    // Helper function to check if country is in list
    function _isCountryInList(bytes32 country) private view returns (bool) {
        uint256 length = countryList.length;
        for (uint256 i = 0; i < length; i++) {
            if (countryList[i] == country) {
                return true;
            }
        }
        return false;
    }

    function _update(address from, address to, uint256 value) 
        internal 
        override(ERC20, ERC20Pausable) // Specify all overridden contracts
    {
        require(!_frozenAccounts[from], "ERC20: account is frozen");
        if (from != address(0)) {
            require(_verifyWhitelisted(from), "ERC20: sender not whitelisted");
        }
        require(_verifyWhitelisted(to), "ERC20: receiver not whitelisted");
        super._update(from, to, value);
    }

    function addFundManager(address account) public {
        grantRole(FUND_MANAGER_ROLE, account);
    }

    function removeFundManager(address account) public {
        revokeRole(FUND_MANAGER_ROLE, account);
    }

}
