# @version 0.2.12
"""
@title Arbie FlashBots Edition
@author Edward Amor
"""


CRYPTOSWAP_ADDR: constant(address) = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46
UNIV2_FACTORY_ADDR: constant(address) = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
UNIV2_ROUTER_ADDR: constant(address) = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
UNIV3_QUOTER_ADDR: constant(address) = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6
MAX_HOPS: constant(uint256) = 25
N_COINS: constant(uint256) = 3


struct ExactInputParams:
    path: Bytes[2048]  # sequence of tightly packed (address + uint24 + address)
    recipient: address
    deadline: uint256
    amountIn: uint256
    amountOutMinimum: uint256


interface CryptoSwap:
    def coins(i: uint256) -> address: view
    def exchange(i: uint256, j: uint256, dx: uint256, min_dy: uint256): nonpayable
    def get_dy(i: uint256, j: uint256, dx: uint256) -> uint256: view

interface ERC20:
    def approve(_spender: address, _value: uint256): nonpayable
    def balanceOf(_owner: address) -> uint256: view
    def transfer(_receiver: address, _value: uint256): nonpayable
    def transferFrom(_owner: address, _receiver: address, _value: uint256): nonpayable

interface Quoter:
    def quoteExactInput(path: Bytes[2048], amountIn: uint256) -> uint256: nonpayable

interface UniV2Factory:
    def getPair(tokenA: address, tokenB: address) -> address: view

interface UniV2Pair:
    def getReserves() -> (uint256, uint256, uint256): view  # reserve0, reserve1, blockTimestampLast
    def swap(amount0Out: uint256, amount1Out: uint256, to: address, data: Bytes[64]): nonpayable
    def token0() -> address: view
    def token1() -> address: view

interface UniV2Router:
    def getAmountOut(amountIn: uint256, reserveIn: uint256, reserveOut: uint256) -> uint256: view
    def getAmountIn(amountOut: uint256, reserveIn: uint256, reserveOut: uint256) -> uint256: view


coins: address[N_COINS]


@external
def __init__():
    for i in range(N_COINS):
        self.coins[i] = CryptoSwap(CRYPTOSWAP_ADDR).coins(i)


@view
@external
def calc_arbitrage_curve_univ2(
    _i: uint256,
    _j: uint256,
    _dx: uint256,
    _path: address[MAX_HOPS],
) -> (uint256, uint256):
    """
    @notice Calculate output from buying on Curve and selling on UniswapV2
    @param _i The index of the input coin for the initial trade on Curve
    @param _j The index of the output coin for the initial trade on Curve
    @param _dx The amount in of coin at index `_i` for the initial trade on Curve
    @param _path An array of coin addresses to hop through on Uniswap. If empty
        no trades are performed on Uniswap. The final value of `_path` should be
        the same address as the coin at index `_i` in Curve Crypto Swap.
    """
    dy: uint256 = CryptoSwap(CRYPTOSWAP_ADDR).get_dy(_i, _j, _dx)
    curve_min_dy: uint256 = dy
    coin_a: address = self.coins[_j]
    coin_b: address = ZERO_ADDRESS
    pair_addr: address = ZERO_ADDRESS

    coin_a_reserves: uint256 = 0
    coin_b_reserves: uint256 = 0
    block_timestamp_last: uint256 = 0
    for i in range(MAX_HOPS):
        coin_b = _path[i]
        if coin_b == ZERO_ADDRESS:
            break
        pair_addr = UniV2Factory(UNIV2_FACTORY_ADDR).getPair(coin_a, coin_b)
        coin_a_reserves, coin_b_reserves, block_timestamp_last = UniV2Pair(pair_addr).getReserves()
        dy = UniV2Router(UNIV2_ROUTER_ADDR).getAmountOut(dy, coin_a_reserves, coin_b_reserves)
        coin_a = coin_b

    return curve_min_dy, dy


@view
@external
def calc_arbitrage_univ2_curve(
    _i: uint256,
    _j: uint256,
    _dx: uint256,
    _path: address[MAX_HOPS],
) -> (uint256, uint256):
    """
    @notice Calculate output from buying on UniswapV2 and selling on Curve
    @param _i The index of the input coin for the final trade on Curve
    @param _j The index of the output coin for the final trade on Curve
    @param _dx The amount in for the initial swap on Uniswap. If `_path` is empty
        this is the value supplied of coin at index `_i` for trading on Curve.
    @param _path An array of coin addresses to hop through on Uniswap. If empty
        no trades are performed on Uniswap. The address of coin at index `_j` should
        be the same as the first address in `_path`.
    """
    dy: uint256 = _dx
    coin_a: address = ZERO_ADDRESS
    coin_b: address = ZERO_ADDRESS
    pair_addr: address = ZERO_ADDRESS

    coin_a_reserves: uint256 = 0
    coin_b_reserves: uint256 = 0
    block_timestamp_last: uint256 = 0
    for i in range(MAX_HOPS - 1):
        coin_a = _path[i]
        coin_b = _path[i + 1]
        if coin_b == ZERO_ADDRESS:
            break
        pair_addr = UniV2Factory(UNIV2_FACTORY_ADDR).getPair(coin_a, coin_b)
        coin_a_reserves, coin_b_reserves, block_timestamp_last = UniV2Pair(pair_addr).getReserves()
        dy = UniV2Router(UNIV2_ROUTER_ADDR).getAmountOut(dy, coin_a_reserves, coin_b_reserves)

    univ2_min_amount: uint256 = dy
    dy = CryptoSwap(CRYPTOSWAP_ADDR).get_dy(_i, _j, dy)
    return univ2_min_amount, dy


@external
def calc_arbitrage_curve_univ3(
    _i: uint256,
    _j: uint256,
    _dx: uint256,
    _path: Bytes[2048],
) -> uint256:
    """
    @notice Calculate output from buying on Curve and selling on UniswapV3
    @dev Off-chain calls should change the stateMutability for this function
        in the ABI to view.
    @param _i The index of the input coin for the initial trade on Curve
    @param _j The index of the output coin for the initial trade on Curve
    @param _dx The amount in of coin at index `_i` for the initial trade on Curve
    @param _path Sequence of address + fee (uint24) + address passed to the Uniswap V3 Quoter
    """
    dy: uint256 = CryptoSwap(CRYPTOSWAP_ADDR).get_dy(_i, _j, _dx)
    return Quoter(UNIV3_QUOTER_ADDR).quoteExactInput(_path, dy)


@external
def calc_arbitrage_univ3_curve(
    _i: uint256,
    _j: uint256,
    _dx: uint256,
    _path: Bytes[2048],
) -> uint256:
    """
    @notice Calculate output from buying on UniswapV3 and selling on Curve
    @dev Off-chain calls should change the stateMutability for this function
        in the ABI to view.
    @param _i The index of the input coin for the final trade on Curve
    @param _j The index of the output coin for the final trade on Curve
    @param _dx The amount in for the initial swap on Uniswap
    @param _path Sequence of address + fee (uint24) + address passed to the Uniswap V3 Quoter
    """
    dy: uint256 = Quoter(UNIV3_QUOTER_ADDR).quoteExactInput(_path, _dx)
    return  CryptoSwap(CRYPTOSWAP_ADDR).get_dy(_i, _j, dy)
