// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'MadChange';

    address tokenAddr = 0x99bbA657f2BbC93c02D617f8bA121cB8Fc104Acf;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) private lps; 
     
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 0;                
    uint private swap_fee_denominator = 100;

    uint private constant exchange_rate_denominator = 10**8;  // we get max and min exchange rates by deviding them with this
                                                    // this is how it is set up in exchange.js

    // Constant: x * y = k
    uint private k;

    constructor() {}
    

    uint private constant denominator = 10**4;

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        uint adding_eth;
        uint adding_token;

        // ==============if we should check the rate before:===============
        // require (token_reserves / eth_reserves < max_exchange_rate / exchange_rate_denominator, "slippage triggered");  
        // we can modify this, without having to change the inequality sign, because there are no negative variables here
        require (eth_reserves * exchange_rate_denominator < max_exchange_rate * token_reserves, "max_exchange_rate was triggered");
        require (eth_reserves * exchange_rate_denominator > min_exchange_rate * token_reserves, "max_exchange_rate was triggered");
 


        adding_eth = msg.value;
        adding_token = divideAndAdjust(adding_eth * token_reserves, eth_reserves);

        require(token.balanceOf(address(msg.sender)) >= adding_token, "Not enough tokens to add liquidity.");
        require(address(msg.sender).balance >= adding_eth, "Not enough ETH to add liquidity.");

        token.transferFrom(msg.sender, address(this), adding_token);

        bool new_lp = true;
        for (uint i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] == msg.sender) 
                new_lp = false; 
            else{
                //lps[lp_providers[i]] = (((eth_reserves * (lps[lp_providers[i]] / denominator))) / (eth_reserves + adding_eth)) * denominator;  
                lps[lp_providers[i]] = eth_reserves * lps[lp_providers[i]] / (eth_reserves + adding_eth);
            }
        }


        if (new_lp){
            lp_providers.push(msg.sender);

            lps[msg.sender] = denominator * adding_eth / (eth_reserves + adding_eth);   
        }else{
            lps[msg.sender] = denominator * ((eth_reserves * (lps[msg.sender] / denominator)) + adding_eth) / (eth_reserves + adding_eth);   
        }
        
        eth_reserves = address(this).balance; 
        token_reserves = token.balanceOf(address(this));

        k = eth_reserves * token_reserves;
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountEth, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        /******* TODO: Implement this function *******/

        // ==============if we should check the rate before:===============
        // require (token_reserves / eth_reserves < max_exchange_rate / exchange_rate_denominator, "slippage triggered");  
        // we can modify this, without having to change the inequality sign, because there are no negative variables here
        require (eth_reserves * exchange_rate_denominator < max_exchange_rate * token_reserves, "max_exchange_rate was triggered");
        require (eth_reserves * exchange_rate_denominator > min_exchange_rate * token_reserves, "max_exchange_rate was triggered");

        uint removing_eth = amountEth;
        uint removing_token = removing_eth * token_reserves / eth_reserves;

        uint myRemains = eth_reserves * lps[msg.sender] / denominator - removing_eth;
        require(myRemains * denominator / (eth_reserves - removing_eth)  >= 0, "Stake can't be less than 0.");
        lps[msg.sender] = myRemains * denominator / (eth_reserves - removing_eth);

        for (uint i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] != msg.sender) 
                lps[lp_providers[i]] = eth_reserves * lps[lp_providers[i]] / (eth_reserves - removing_eth);
        }

        payable(msg.sender).transfer(removing_eth);
        token.transfer(msg.sender, removing_token);

        eth_reserves = address(this).balance; 
        token_reserves = token.balanceOf(address(this));

        k = eth_reserves * token_reserves;
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        /******* TODO: Implement this function *******/

        // ==============if we should check the rate before:===============
        // require (token_reserves / eth_reserves < max_exchange_rate / exchange_rate_denominator, "slippage triggered");  
        // we can modify this, without having to change the inequality sign, because there are no negative variables here
        require (eth_reserves * exchange_rate_denominator < max_exchange_rate * token_reserves, "max_exchange_rate was triggered");
        require (eth_reserves * exchange_rate_denominator > min_exchange_rate * token_reserves, "max_exchange_rate was triggered");
 
        uint removing_eth = divideAndAdjust(lps[msg.sender] * eth_reserves, denominator);
        uint removing_token = removing_eth * token_reserves / eth_reserves;

        uint myRemains = divideAndAdjust( eth_reserves * lps[msg.sender], denominator) - removing_eth;
        
        require(myRemains == 0, "Something went wrong, since the remaining stake is not 0.");
        lps[msg.sender] = divideAndAdjust(denominator * myRemains, (eth_reserves - removing_eth));

        for (uint i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] != msg.sender) 
                lps[lp_providers[i]] = divideAndAdjust(eth_reserves * lps[lp_providers[i]], (eth_reserves - removing_eth));
        }

        payable(msg.sender).transfer(removing_eth);
        token.transfer(msg.sender, removing_token);

        eth_reserves = address(this).balance; 
        token_reserves = token.balanceOf(address(this));

        k = eth_reserves * token_reserves;

        for (uint i = 0; i < lp_providers.length; i++) {
            if (lp_providers[i] == msg.sender) 
                removeLP(i);
        }
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        uint tokenSupply = token.balanceOf(msg.sender);

        require(amountTokens <= tokenSupply, "Sender does not have enough tokens for swap");
        require (amountTokens > 0, "Need tokens to swap.");

        // ==============if we should check the rate before:===============
        // require (token_reserves / eth_reserves < max_exchange_rate / exchange_rate_denominator, "slippage triggered");  
        // we can modify this, without having to change the inequality sign, because there are no negative variables here
        require (token_reserves * exchange_rate_denominator < max_exchange_rate * eth_reserves, "max_exchange_rate was triggered");
 
        token_reserves += amountTokens;
        uint newEthReserves = divideAndAdjust(k, token_reserves);
        uint ethToSend = eth_reserves - newEthReserves;
        eth_reserves = newEthReserves;

        require (token_reserves >= 1, "MDT pool depleted");
        require (eth_reserves >= 1, "ETH pool depleted");

        // If everything passes we can swap
        payable(msg.sender).transfer(ethToSend);
        token.transferFrom(msg.sender, address(this), amountTokens);
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/

        require (msg.value > 0, "Need ETH to swap.");
        require(msg.value <= eth_reserves, "Sender does not have enough tokens for swap");

        // ==============if we should check the rate before:===============
        // require (eth_reserves / roken_reserves < max_exchange_rate / exchange_rate_denominator, "slippage triggered");  
        // we can modify this, without having to change the inequality sign, because there are no negative variables here
        require (eth_reserves * exchange_rate_denominator < max_exchange_rate * token_reserves, "max_exchange_rate was triggered");

        eth_reserves += msg.value;
        uint newTokenReserves = divideAndAdjust(k , eth_reserves);
        uint tokensToSend = token_reserves - newTokenReserves;
        token_reserves = newTokenReserves;


        require (token_reserves >= 1, "Token reserves depleted");
        require (eth_reserves >= 1, "ETH reserves depleted");

        token.transfer(msg.sender, tokensToSend);
    }

    function divideAndAdjust(uint dividend, uint divisor) private pure returns(uint) {
        uint quotient = dividend * 100 / divisor;
        uint remainder = quotient % 100;
        quotient /= 100;
        if(remainder >= 50){
            quotient += 1;
        }
        return quotient;
    }
}
