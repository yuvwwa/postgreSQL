-- таблица пользователей с учетом военных должностей

create table users (
	id integer primary key not null,
	username varchar (100),
	military_position varchar (100)
);

create table measurement_batch (
	id integer primary key not null,
	startperiod timestamp without time zone default now(),
	positionx numeric(3,2),
	positiony numeric(3,2),
	username varchar(100)
);

alter table measurement_batch rename column username to user_name;
