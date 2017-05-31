create table if not exists dbFlipped.Flipped
(
    ID              int unsigned    not null AUTO_INCREMENT,
    SendTo          bigint          not null default 0,
    Contents        varchar(4096)   not null default '',
    Lat             double          not null default 0,
    Lng             double          not null default 0,
    GeoHash         varchar(32)     not null default '',
    primary key(ID),
    index(ID, SendTo),
    index(ID, GeoHash)
)ENGINE=InnoDB AUTO_INCREMENT=1000000 DEFAULT CHARSET=latin1;