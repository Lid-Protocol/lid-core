pragma solidity 0.5.16;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "./interfaces/ILidCertifiableToken.sol";

contract LidPromoFund is Initializable {
    using SafeMath for uint256;

    ILidCertifiableToken private lidToken;
    address public authorizor;
    address public releaser;

    uint256 public totalLidAuthorized;
    uint256 public totalLidReleased;

    uint256 public totalEthAuthorized;
    uint256 public totalEthReleased;

    mapping(address => bool) authorizors;

    mapping(address => bool) releasers;

    function initialize(
        address _authorizor,
        address _releaser,
        ILidCertifiableToken _lidToken
    ) external initializer {
        lidToken = _lidToken;
        authorizor = _authorizor;
        releaser = _releaser;
    }

    function() external payable {}

    function releaseLidToAddress(address receiver, uint256 amount) external {
        require(msg.sender == authorizor, "Can only be called by authorizor.");
        lidToken.transfer(receiver, amount);
    }

    function releaseEthToAddress(address payable receiver, uint256 amount)
        external
    {
        require(msg.sender == authorizor, "Can only be called by authorizor.");
        receiver.transfer(amount);
    }
}
