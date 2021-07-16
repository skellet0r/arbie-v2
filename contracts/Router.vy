# @version 0.2.12
"""
@title Call Proxy for arbitrage contracts
"""


WETH: constant(address) = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2


interface WETH9:
    def deposit(): payable
    def withdraw(_value: uint256): nonpayable

interface ERC20:
    def approve(_spender: address, _value: uint256): nonpayable
    def decimals() -> uint256: view
    def balanceOf(_owner: address) -> uint256: view
    def transfer(_to: address, _value: uint256): nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256): nonpayable

interface PriceFeed:
    def latestRoundData() -> (uint256, int256, uint256, uint256, uint256): view


owner: public(address)
future_owner: public(address)

price_feeds: public(HashMap[address, address])  # coin / ETH price feed


@payable
@external
def __default__():
    pass


@external
def __init__(_coins: address[8], _price_feeds: address[8]):
    self.owner = msg.sender
    for i in range(8):
        self.price_feeds[_coins[i]] = _price_feeds[i]


@external
def commit_transfer_ownership(_owner: address):
    assert msg.sender == self.owner  # dev: only owner
    self.future_owner = _owner


@external
def accept_transfer_ownership():
    owner: address = self.future_owner
    assert msg.sender == owner  # dev: only future owner
    self.owner = owner


@external
def revert_transfer_ownership():
    assert msg.sender == self.owner  # dev: only owner
    self.future_owner = ZERO_ADDRESS



@external
def flashbot_arbitrage(_contract: address, _coin: address, _dx: uint256, _calldata: Bytes[8192]):
    owner: address = self.owner
    assert msg.sender == owner

    ERC20(_coin).transferFrom(owner, _contract, _dx)
    raw_call(_contract, _calldata)

    revenue: uint256 = ERC20(_coin).balanceOf(self)
    profit: uint256 = revenue - _dx
    precision: uint256 = 10 ** ERC20(_coin).decimals()

    ERC20(_coin).transfer(msg.sender, revenue)

    roundId: uint256 = 0
    price: int256 = 10 ** 18
    startedAt: uint256 = 0
    updatedAt: uint256 = 0
    answeredInRound: uint256 = 0

    if _coin != WETH:
        roundId, price, startedAt, updatedAt, answeredInRound = PriceFeed(self.price_feeds[_coin]).latestRoundData()

    profit_in_eth: uint256 = profit * convert(price, uint256) / precision
    miner_fee: uint256 = 90 * profit_in_eth / 100
    eth_balance: uint256 = self.balance
    if eth_balance < miner_fee:
        WETH9(WETH).withdraw(miner_fee - eth_balance)

    raw_call(block.coinbase, b"", value=miner_fee)


@external
def withdraw():
    owner: address = self.owner
    assert msg.sender == owner

    weth_balance: uint256 = ERC20(WETH).balanceOf(self)
    if weth_balance > 0:
        WETH9(WETH).withdraw(weth_balance)
    raw_call(owner, b"", value=self.balance)

@external
def withdraw_token(_coin: address, _amount: uint256):
    assert msg.sender == self.owner
    ERC20(_coin).transfer(msg.sender, _amount)
