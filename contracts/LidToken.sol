pragma solidity 0.5.16;
import "./uniswapV2Periphery/interfaces/IUniswapV2Router01.sol";
import "./interfaces/IXEth.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Pausable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./library/BasisPoints.sol";
import "./interfaces/ILidCertifiableToken.sol";
import "./LidStaking.sol";
import "./LidCertifiedPresale.sol";

contract LidToken is
    Initializable,
    ILidCertifiableToken,
    ERC20Burnable,
    ERC20Mintable,
    ERC20Pausable,
    ERC20Detailed,
    Ownable
{
    using BasisPoints for uint256;
    using SafeMath for uint256;

    uint256 public taxBP;
    uint256 public daoTaxBP;
    address private daoFund;
    LidStaking private lidStaking;
    LidCertifiedPresale private lidPresale;

    bool public isTaxActive;
    bool public isTransfersActive;

    mapping(address => bool) private trustedContracts;
    mapping(address => bool) public taxExempt;
    mapping(address => bool) public fromOnlyTaxExempt;
    mapping(address => bool) public toOnlyTaxExempt;

    string private _name;

    modifier onlyPresaleContract() {
        require(
            msg.sender == address(lidPresale),
            "Can only be called by presale sc."
        );
        _;
    }

    function initialize(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address owner,
        uint256 _taxBP,
        uint256 _daoTaxBP,
        address _daoFund,
        LidStaking _lidStaking,
        LidCertifiedPresale _lidPresale
    ) external initializer {
        taxBP = _taxBP;
        daoTaxBP = _daoTaxBP;

        Ownable.initialize(msg.sender);

        ERC20Detailed.initialize(name, symbol, decimals);

        ERC20Mintable.initialize(address(this));
        _removeMinter(address(this));
        _addMinter(owner);

        ERC20Pausable.initialize(address(this));
        _removePauser(address(this));
        _addPauser(owner);

        daoFund = _daoFund;
        lidStaking = _lidStaking;
        addTrustedContract(address(_lidStaking));
        addTrustedContract(address(_lidPresale));
        setTaxExemptStatus(address(_lidStaking), true);
        setTaxExemptStatus(address(_lidPresale), true);
        //Due to issue in oz testing suite, the msg.sender might not be owner
        _transferOwnership(owner);
    }

    function xethLiqTransfer(
        IUniswapV2Router01 router,
        address pair,
        IXEth xeth,
        uint256 minWadExpected
    ) external onlyOwner {
        isTaxActive = false;
        uint256 lidLiqWad = balanceOf(pair).sub(1 ether);
        _balances[pair] = _balances[pair].sub(lidLiqWad);
        _balances[address(this)] = _balances[address(this)].add(lidLiqWad);
        approve(router, lidLiqWad);
        router.swapExactTokensForETH(
            lidLiqWad,
            minWadExpected,
            [address(this)],
            address(this),
            now
        );
        _balances[pair] = _balances[pair].sub(lidLiqWad);
        _balances[address(this)] = _balances[address(this)].add(lidLiqWad);
        xeth.wrap.value(address(this).balance)();
        require(
            xeth.balanceOf(address(this)) >= minWadExpected,
            "Less xeth than expected."
        );

        router.addLiquidity(
            address(this),
            address(xeth),
            lidLiqWad,
            xeth.balanceOf(address(this)),
            lidLiqWad,
            xeth.balanceOf(address(this)),
            address(0x0),
            now
        );

        isTaxActive = true;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(isTransfersActive, "Transfers are currently locked.");
        (isTaxActive &&
            !taxExempt[msg.sender] &&
            !taxExempt[recipient] &&
            !toOnlyTaxExempt[recipient] &&
            !fromOnlyTaxExempt[msg.sender])
            ? _transferWithTax(msg.sender, recipient, amount)
            : _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(isTransfersActive, "Transfers are currently locked.");
        (isTaxActive &&
            !taxExempt[sender] &&
            !taxExempt[recipient] &&
            !toOnlyTaxExempt[recipient] &&
            !fromOnlyTaxExempt[sender])
            ? _transferWithTax(sender, recipient, amount)
            : _transfer(sender, recipient, amount);
        if (trustedContracts[msg.sender]) return true;
        approve(
            msg.sender,
            allowance(sender, msg.sender).sub(
                amount,
                "Transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function addTrustedContract(address contractAddress) public onlyOwner {
        trustedContracts[contractAddress] = true;
    }

    function setTaxExemptStatus(address account, bool status) public onlyOwner {
        taxExempt[account] = status;
    }

    function findTaxAmount(uint256 value)
        public
        view
        returns (uint256 tax, uint256 daoTax)
    {
        tax = value.mulBP(taxBP);
        daoTax = value.mulBP(daoTaxBP);
    }

    function _transferWithTax(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        (uint256 tax, uint256 daoTax) = findTaxAmount(amount);
        uint256 tokensToTransfer = amount.sub(tax).sub(daoTax);

        _transfer(sender, address(lidStaking), tax);
        _transfer(sender, address(daoFund), daoTax);
        _transfer(sender, recipient, tokensToTransfer);
        lidStaking.handleTaxDistribution(tax);
    }
}
