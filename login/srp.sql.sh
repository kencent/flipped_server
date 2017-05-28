for (( db=0;db<10;db=db+1 ))
do
	echo "create database if not exists dbLogin_${db};"
	for (( tb=0;tb<100;tb=tb+1 ))
	do
		echo "
create table if not exists dbLogin_${db}.SRP_${tb}
(
    I             	bigint     		not null default 0,
    v            	varchar(4096)   not null default '',
    s            	varchar(1024)   not null default '',
    K    			varchar(4096) 	not null default '',
    ValidTime       bigint    		not null default 0,
    LongValidTime   bigint    		not null default 0,
    primary key(I)
)ENGINE=InnoDB DEFAULT CHARSET=latin1;
		"
	done
done