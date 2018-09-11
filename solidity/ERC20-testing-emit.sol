pragma solidity ^0.4.24;
contract REGISTER {
    mapping(address => string) issuebook;
    event eTest(address, string);
    function register(
            address myaddr,
            string myissue
        )
            public
        {
            issuebook[myaddr] = myissue;
            emit eTest(myaddr, myissue);
        }
        
        function find(
            address myaddr    
        )
            public
            view
        returns(string){
            return issuebook[myaddr];
        }
    
}
