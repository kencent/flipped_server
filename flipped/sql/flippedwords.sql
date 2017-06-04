create table if not exists dbFlipped.Flipped
(
    ID                  int unsigned    not null AUTO_INCREMENT,
    Uid 		        bigint 			not null default 0, 
    SendTo              bigint          not null default 0,
    CTime 			    bigint 			not null default 0,
    Contents            varchar(4096)   not null default '',
    Lat                 double          not null default 0,
    Lng                 double          not null default 0,
    GeoHash             varchar(32)     not null default '',
    Status			    int 			not null default 0,
    StatusUpdateTime    bigint          not null default 0,
    primary key(ID),
    index(SendTo, ID),
    index(STATUS, GeoHash, ID)
)ENGINE=InnoDB AUTO_INCREMENT=1000000 DEFAULT CHARSET=latin1;

create table if not exists dbFlipped.FeedBacks
(
    ID                  int unsigned    not null AUTO_INCREMENT,
    Uid                 bigint          not null default 0, 
    CTime               bigint          not null default 0,
    Contents            varchar(4096)   not null default '',
    primary key(ID)
)ENGINE=InnoDB AUTO_INCREMENT=1000000 DEFAULT CHARSET=latin1;