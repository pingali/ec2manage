CREATE DATABASE repl;
use repl;
CREATE TABLE `checksum` (
`db` char(64) NOT NULL,
`tbl` char(64) NOT NULL,
`chunk` int(11) NOT NULL,
`boundaries` char(64) NOT NULL,
`this_crc` char(40) NOT NULL,
`this_cnt` int(11) NOT NULL,
`master_crc` char(40) default NULL,
`master_cnt` int(11) default NULL,
`ts` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
PRIMARY KEY (`db`,`tbl`,`chunk`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

