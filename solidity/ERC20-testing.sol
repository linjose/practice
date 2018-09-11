pragma solidity ^0.4.24;
contract REGISTER {
    mapping(address => string) issuebook;
    function register(
            address myaddr,
            string myissue
        )
            public
        {
            issuebook[myaddr] = myissue;
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
