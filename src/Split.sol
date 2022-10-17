// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// A Split is a smart contract that receives and distributes ETH and ERC20 tokens
// Each Split has an address to which tokens can be sent (address deployed)
// Splits have a set of Recipients with corresponding ownership percentages
// Splits a list of balances for each token it's received -- in this case, only ETH
// Splits have a distribution fee for the protocol for every distribution

/**
 * ERRORS
 */

contract MainSplit {

    /// @notice holds Split metadata
  struct Split {
    bytes32 hash;
    address controller;
    address newPotentialController;
  }

    /// @notice constant to scale uints into percentages (1e6 == 100%)
    uint256 public constant PERCENTAGE_SCALE = 1e6;
    /// @notice maximum distributor fee; 1e5 = 10% * PERCENTAGE_SCALE
    uint256 internal constant MAX_DISTRIBUTOR_FEE = 1e5;
    /// @notice mapping to account ETH balances
    mapping(address => uint256) internal ethBalances;
    // mapping to see if address is listed in contract
    mapping (address => bool) public Accounts;
     /// @notice mapping to Split metadata
    mapping(address => Split) internal splits;

    address[] internal _payees;


//   modifier validSplit(
//     address[] memory accounts,
//     uint32[] memory percentAllocations,
//     uint32 distributorFee
//   ) {}

//     modifier onlySplitController(address split) {
//     if (msg.sender != splits[split].controller) revert Unauthorized(msg.sender);
//     _;
//   }

  /**
   * EVENTS
   */

    // emitted after ETH is distributed
    event DistributeETH(
    address indexed split,
    uint256 amount,
    address indexed distributorAddress
  );

    // @notice emitted after each successful split update
    event UpdateSplit(address indexed split);
    // @notice emitted after each successful split creation
    event CreateSplit(address indexed split);
    // @notice emitted after each initiated split control transfer
    event InitiateControlTransfer(
    address indexed split,
    address indexed newPotentialController
  );


   // CONSTRUCTOR

    // @notice Deploy a new Split instance
  constructor(
    address[] memory accounts,
    uint32[] memory percentAllocations,
    uint32 distributorFee,
    address controller) payable 
    // validSplit(accounts, percentAllocations, distributorFee) -- modifier add later
    {
       bytes32 splitHash = keccak256(abi.encodePacked(accounts, percentAllocations, distributorFee, controller));
    // store new hash in storage for future verification
    splits[address(this)].hash = splitHash;
    emit CreateSplit(address(this));
    }

    // @notice Receive ETH
    receive() external payable {}


    // includes validSplit modifier to ensure split is valid
    // allows an account listed to withdraw ETH
function withdrawETH (address split,
    address[] calldata accounts,
    uint32[] calldata percentAllocations,
    uint32 distributorFee,
    address distributorAddress) external {

    // calls internal function to distribute ETH
    _distributeETH(
      split,
      accounts,
      percentAllocations,
      distributorFee,
      distributorAddress
    );
  }

 // @notice Distributes the ETH balance for split `split`
  function _distributeETH(
    address split,
    address[] memory accounts,
    uint32[] memory percentAllocations,
    uint32 distributorFee,
    address distributorAddress
  ) internal {
    uint256 mainBalance = ethBalances[split];
    uint256 proxyBalance = split.balance;
    // if mainBalance is positive, leave 1 in SplitMain for gas efficiency
    uint256 amountToSplit;
    unchecked {
      // underflow should be impossible
      if (mainBalance > 0) mainBalance -= 1;
      // overflow should be impossible
      amountToSplit = mainBalance + proxyBalance;
    }
    if (mainBalance > 0) ethBalances[split] = 1;
    // emit event with gross amountToSplit (before deducting distributorFee)
    emit DistributeETH(split, amountToSplit, distributorAddress);
    if (distributorFee != 0) {
      // given `amountToSplit`, calculate keeper fee
      uint256 distributorFeeAmount = _scaleAmountByPercentage(
        amountToSplit,
        distributorFee
      );
      unchecked {
        // credit keeper with fee
        // overflow should be impossible with validated distributorFee
        ethBalances[
          distributorAddress != address(0) ? distributorAddress : msg.sender
        ] += distributorFeeAmount;
        // given keeper fee, calculate how much to distribute to split recipients
        // underflow should be impossible with validated distributorFee
        amountToSplit -= distributorFeeAmount;
      }
    }
  }

    // @notice Multiplies an amount by a scaled percentage
    function _scaleAmountByPercentage(uint256 amount, uint256 scaledPercent)
    internal
    pure
    returns (uint256 scaledAmount)
  {
    // use assembly to bypass checking for overflow & division by 0
    // scaledPercent has been validated to be < PERCENTAGE_SCALE)
    // & PERCENTAGE_SCALE will never be 0
    // pernicious ERC20s may cause overflow, but results do not affect ETH & other ERC20 balances
    assembly {
      /* eg (100 * 2*1e4) / (1e6) */
      scaledAmount := div(mul(amount, scaledPercent), PERCENTAGE_SCALE)
    }
  }

    // @notice Updates & distributes the ETH balance for split `split`
  function updateAndDistributeETH(
    address split,
    address[] calldata accounts,
    uint32[] calldata percentAllocations,
    uint32 distributorFee,
    address distributorAddress
  )
    external
    // onlySplitController(split) -- modifier enable later
    // validSplit(accounts, percentAllocations, distributorFee) -- modifier enable later
  {
    _updateSplit(split, accounts, percentAllocations, distributorFee);
    // know splitHash is valid immediately after updating; only accessible via controller
    _distributeETH(
      split,
      accounts,
      percentAllocations,
      distributorFee,
      distributorAddress
    );
  }

  // @notice Begins transfer of the controlling address of mutable split `split` to `newController`

  function transferControl(address split, address newController)
    external
    // onlySplitController(split) -- modifier
    // validNewController(newController) -- modifier
  {
    splits[split].newPotentialController = newController;
    emit InitiateControlTransfer(split, newController);
  }


  function _updateSplit(
    address split,
    address[] calldata accounts,
    uint32[] calldata percentAllocations,
    uint32 distributorFee
  ) internal {
    bytes32 splitHash = keccak256(abi.encodePacked(accounts, percentAllocations, distributorFee));
    // store new hash in storage for future verification
    splits[split].hash = splitHash;
    emit UpdateSplit(split);
  }
    

  // VIEW FUNCTIONS

    // @notice Returns the current controller of split `split`
  function getController(address split) external view returns (address) {
    return splits[split].controller;
  }

    // @notice Returns the current ETH balance of account `account`
  function getETHBalance(address account) external view returns (uint256) {
    return
      ethBalances[account] + (splits[account].hash != 0 ? account.balance : 0);
  }
}