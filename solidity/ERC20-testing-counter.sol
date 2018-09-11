pragma solidity ^0.4.24;
contract test1 {
    uint256 i = 0;
    mapping(address => bool) addresscount;
    mapping(address => string) addressbook;
    event eTest(address, string);
    function register(
        address myaddr,
        string myurl
    )
        public
    {
        addressbook[myaddr] = myurl;
        counter(myaddr);
        emit eTest(myaddr, myurl);
    }
    function counter(
        address myaddr
    )
        private
    {
        if(addresscount[myaddr]) {
            // 已存在
        } else {
            addresscount[myaddr] = true;
            i += 1;
        }
    }
    function find(
        address myaddr
    )
        public
        view
    returns(string) {
        return addressbook[myaddr];
    }
    
    function getSize(
    )
        public
        view
    returns(uint256) {
        return i;
    }
}
