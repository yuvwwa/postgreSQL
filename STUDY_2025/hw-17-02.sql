do $$
begin
raise notice 'Запускаем создание новой структуры базы данных meteo'; 
begin

/*
 1. Удаляем старые элементы
 ======================================
 */

    DROP SCHEMA IF EXISTS yulya CASCADE;
    DROP FUNCTION IF EXISTS yulya."fnHeaderGetPressure"();
    DROP FUNCTION IF EXISTS yulya."fnHeaderGetPressure"(pressure numeric);
    DROP FUNCTION IF EXISTS yulya."getDate"();
    DROP FUNCTION IF EXISTS yulya."getHeight"(height integer);
    DROP FUNCTION IF EXISTS yulya."getBBBTT"(params yulya.send_params);
    DROP FUNCTION IF EXISTS yulya."calculate_interpolation"(var_temperature integer);
    DROP TYPE IF EXISTS yulya.interpolation_type;
    DROP TYPE IF EXISTS yulya.send_params;
    DROP TABLE IF EXISTS yulya.calc_temperatures_correction;
    DROP TABLE IF EXISTS yulya.const;
    DROP TABLE IF EXISTS yulya.measure_settings;
    DROP TABLE IF EXISTS yulya.measurment_baths;
    DROP TABLE IF EXISTS yulya.measurment_input_params;
    DROP TABLE IF EXISTS yulya.measurment_types;
    DROP TABLE IF EXISTS yulya.military_ranks CASCADE;
    DROP TABLE IF EXISTS yulya.employees CASCADE;
    DROP SEQUENCE IF EXISTS yulya.employees_seq;
    DROP SEQUENCE IF EXISTS yulya.measure_settings_seq;
    DROP SEQUENCE IF EXISTS yulya.measurment_baths_seq;
    DROP SEQUENCE IF EXISTS yulya.measurment_input_params_seq;
    DROP SEQUENCE IF EXISTS yulya.measurment_types_seq;
    DROP SEQUENCE IF EXISTS yulya.military_ranks_seq;

end;

/*
 2. Добавляем структуры данных 
 ================================================
 */

-- Схема
CREATE SCHEMA yulya;
ALTER SCHEMA yulya OWNER TO pg_database_owner;
COMMENT ON SCHEMA yulya IS 'standard yulya schema';


-- Типы
CREATE TYPE yulya.interpolation_type AS (
	x0 numeric(8,2),
	x1 numeric(8,2),
	y0 numeric(8,2),
	y1 numeric(8,2)
);

-- Новое задание
-- (2. Создать собственный тип данных для передачи входных параметров)
CREATE TYPE yulya.send_params AS (
	temperature numeric(8,2),
	pressure numeric(8,2),
	wind_direction numeric(8,2)
);

ALTER TYPE yulya.interpolation_type OWNER TO admin;
ALTER TYPE yulya.send_params OWNER TO admin;


-- Функции

-- Классная работа

/*
CREATE FUNCTION yulya."fnHeaderGetPressure"() 
	RETURNS numeric
    LANGUAGE plpgsql
AS $$
declare 
	var_result numeric(8,2);
begin
	var_result := yulya."fnHeaderGetPressureWithParametr"(700.00);
	return var_result;
end;
$$;

CREATE FUNCTION yulya."fnHeaderGetPressure"(pressure numeric) 
	RETURNS numeric
    LANGUAGE 'plpgsql'
AS $$
declare
	var_result numeric(8,2);
begin
	var_result := pressure - 750;

	if var_result < 0 then
		var_result := var_result - 500;
	end if;
	
	return abs(var_result);
end;
$$;
*/

-- Классная работа + доделать дома
-- Метео-средний + интерполяция

-- Дата
CREATE FUNCTION yulya."getDate"() RETURNS numeric
    LANGUAGE plpgsql
    AS $$
begin
	return format('%s%s%s', substring(now()::text, 9,2), substring(now()::text, 12,2), substring(now()::text, 15,1));
end;
$$;

-- Высота
CREATE FUNCTION yulya."getHeight"(height integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	var_len integer default 0;
	var_result text;
begin

var_result := height::text;
raise notice 'len %', length(var_result);

return
	case 
	when length(var_result)=1
	then 
		'000'
	when length(var_result)=2
	then 
		'00'
	when length(var_result)=3
	then 
		'0'
		end || var_result;

end;
$$;

-- БББТТ
CREATE FUNCTION yulya."getBBBTT"(params yulya.send_params) 
	RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	delta_temp integer;
	delta_pres integer;
	BBB text;
	TT text;
	var_result text;
begin
	delta_pres := params.pressure - 750;
    delta_temp := params.temperature;

	if delta_pres >= 0 then
		BBB := case
			when length(delta_pres::text)=1 then '00' || delta_pres
			when length(delta_pres::text)=2 then '0'  || delta_pres
			else delta_pres::text
		end;
	else
		BBB := '5' || case
			when length(abs(delta_pres)::text)=1 then '0' ||abs(delta_pres)
			else abs(delta_pres)::text
		end;
	end if;
	TT := case
		when length(abs(delta_temp)::text)=1 then '0' ||abs(delta_temp)
		else abs(delta_temp)::text
	end;

	var_result := BBB || TT;

	return var_result;
end;
$$;

-- Интерполяция
create function yulya."calculate_interpolation"(var_temperature integer)
    returns numeric
    language plpgsql
    as $$
declare 
	var_interpolation interpolation_type;
	var_result numeric(8,2) default 0;
	var_min_temparure numeric(8,2) default 0;
	var_max_temperature numeric(8,2) default 0;
	var_denominator numeric(8,2) default 0;
begin
	raisenotice 'Расчет интерполяции для температуры %', var_temperature;

	if exists (select 1 from yulya.calc_temperatures_correction where temperature = var_temperature ) then
	begin
		select correction 
		into var_result 
		from yulya.calc_temperatures_correction
		where temperature = var_temperature;
	end;
	else	
	begin
		select min(temperature), max(temperature) 
		into var_min_temparure, var_max_temperature
		from yulya.calc_temperatures_correction;

		if var_temperature < var_min_temparure or var_temperature > var_max_temperature then
			raise exception 'Некорректно передан параметр! Невозможно рассчитать поправку. Значение должно укладываться в диаппазон: %, %',
				var_min_temparure, var_max_temperature;
		end if;   

		select x0, y0, x1, y1 
		into var_interpolation.x0, var_interpolation.y0, var_interpolation.x1, var_interpolation.y1
		from
		(
			select t1.temperature as x0, t1.correction as y0
			from yulya.calc_temperatures_correction as t1
			where t1.temperature <= var_temperature
			order by t1.temperature desc
			limit 1
		) as leftPart
		cross join
		(
			select t1.temperature as x1, t1.correction as y1
			from yulya.calc_temperatures_correction as t1
			where t1.temperature >= var_temperature
			order by t1.temperature 
			limit 1
		) as rightPart;
		
		raisenotice 'Граничные значения %', var_interpolation;

		var_denominator := var_interpolation.x1 - var_interpolation.x0;
		if var_denominator = 0.0 then
			raise exception 'Деление на нуль. Возможно, некорректные данные в таблице с поправками!';
		end if;
		
		var_result := (var_temperature - var_interpolation.x0) * (var_interpolation.y1 - var_interpolation.y0) / var_denominator + var_interpolation.y0;
	
	end;
	end if;

	raisenotice 'Результат: %', var_result;

	return var_result;
end;
$$;



-- Новое задание 
-- (3. Написать собственную функцию на вход должны подаваться входные параметры, а на выходе собственный тип данных.)
-- (4. Функция должна проверять входные параметры. При нарушении граничных параметров формировать raise error)
CREATE FUNCTION yulya.new_data_type(temp numeric, pres numeric, wind numeric) RETURNS yulya.send_params
    LANGUAGE plpgsql
    AS $$
declare
	temp_min numeric(8,2);
	temp_max numeric(8,2);
	pres_min numeric(8,2);
	pres_max numeric(8,2);
	wind_min numeric(8,2);
	wind_max numeric(8,2);
	var_result yulya.send_params;
begin
	select min_value into temp_min from yulya.measure_settings where measure_name = 'temperature';
	select max_value into temp_max from yulya.measure_settings where measure_name = 'temperature';
	select min_value into pres_min from yulya.measure_settings where measure_name = 'pressure';
	select max_value into pres_max from yulya.measure_settings where measure_name = 'pressure';
	select min_value into wind_min from yulya.measure_settings where measure_name = 'wind_direction';
	select max_value into wind_max from yulya.measure_settings where measure_name = 'wind_direction';

	-- 
	if temp < temp_min OR temp > temp_max then
		raise exception 'Температура % выходит за границы интервала [%; %]', 
		temp, temp_min, temp_max;
	end if;
	if pres < pres_min OR pres > pres_max then
		raise exception 'Давление % выходит за границы интервала [%; %]',
		pres, pres_min, pres_max;
	end if;
	if wind < wind_min OR wind > wind_max then 
		raise exception 'Направление ветра % выходит за границы интервала [%; %]',
		wind, wind_min, wind_max;
	end if;

	var_result.temperature := temp;
	var_result.pressure := pres;
	var_result.wind_direction := wind;

	return var_result;

end;
$$;

ALTER FUNCTION yulya."fnHeaderGetPressure"() OWNER TO admin;
ALTER FUNCTION yulya."fnHeaderGetPressure"(pressure numeric) OWNER TO admin;
ALTER FUNCTION yulya."getDate"() OWNER TO admin;
ALTER FUNCTION yulya."getHeight"(height integer) OWNER TO admin;
ALTER FUNCTION yulya."calculate_interpolation"(var_temperature integer) OWNER TO admin;
ALTER FUNCTION yulya."getBBBTT"(params yulya.send_params) OWNER TO admin;

SET default_tablespace = '';
SET default_table_access_method = heap;


-- Таблицы
CREATE TABLE yulya.calc_temperatures_correction (
    temperature numeric(8,2) NOT NULL,
    correction numeric(8,2)
);

CREATE TABLE yulya.const (
    name character varying NOT NULL,
    const text
);

CREATE TABLE yulya.employees (
    id integer NOT NULL,
    name text,
    birthday timestamp without time zone,
    military_rank_id integer
);

-- Новая таблица (1. Создать таблицу с настройками для проверки входных данных measure_settings)
CREATE TABLE yulya.measure_settings (
    id integer NOT NULL,
    measure_name character varying(50),
    min_value numeric(8,2),
    max_value numeric(8,2),
    measure_unit character varying(50)
);

INSERT INTO yulya.measure_settings (id, measure_name, min_value, max_value, measure_unit) VALUES
    (1, 'temperature', -58.00, 58.00, 'Celsius'),
    (2, 'pressure', 500.00, 900.00, 'мм рт ст'),
    (3, 'wind_direction', 0.00, 59.00, 'degrees');

CREATE TABLE yulya.measurment_baths (
    id integer NOT NULL,
    emploee_id integer NOT NULL,
    measurment_input_param_id integer NOT NULL,
    started timestamp without time zone DEFAULT now()
);

CREATE TABLE yulya.measurment_input_params (
    id integer NOT NULL,
    measurment_type_id integer NOT NULL,
    height numeric(8,2) DEFAULT 0,
    temperature numeric(8,2) DEFAULT 0,
    pressure numeric(8,2) DEFAULT 0,
    wind_direction numeric(8,2) DEFAULT 0,
    wind_speed numeric(8,2) DEFAULT 0
);

CREATE TABLE yulya.measurment_types (
    id integer NOT NULL,
    short_name character varying(50),
    description text
);

CREATE TABLE yulya.military_ranks (
    id integer NOT NULL,
    description character varying(255)
);

insert into yulya.calc_temperatures_correction (temperature, correction)
values 
(0.00, 0.50),
(5.00, 0.50),
(10.00, 1.00),
(20.00, 1.00),
(25.00, 2.00),
(30.00, 3.50),
(40.00, 4.50);

insert into yulya.const(name, const)
values 
('for_bbb', '750'),
('for_temp', '15.09');

insert into yulya.employees(id, name, birthday, military_rank_id)
values
(1, 'Кравцова Юлия Евгеньевна', '2004-02-27 10:05:00', 2);

insert into yulya.measurment_baths (id, emploee_id, measurment_input_param_id, started)
values
(1,1,1, now());

insert into yulya.measurment_input_params (id, measurment_type_id, height, temperature, pressure, wind_direction, wind_speed)
values
(1,1,100.00, 12.00, 700.00, 0.20, 45.00);

insert into yulya.measurment_types (id, short_name, description)
values
(1, 'ДМК', 'Десантный метео комплекс'),
(2, 'ВР', 'Ветровое ружье');

insert into yulya.military_ranks (id, description)
values
(1, 'Рядовой'),
(2, 'Лейтенант');

ALTER TABLE yulya.calc_temperatures_correction OWNER TO admin;
ALTER TABLE yulya.const OWNER TO admin;
ALTER TABLE yulya.employees OWNER TO admin;
ALTER TABLE yulya.measure_settings OWNER TO admin;
ALTER TABLE yulya.measurment_baths OWNER TO admin;
ALTER TABLE yulya.measurment_input_params OWNER TO admin;
ALTER TABLE yulya.measurment_types OWNER TO admin;
ALTER TABLE yulya.military_ranks OWNER TO admin;

CREATE SEQUENCE yulya.employees_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE yulya.measure_settings_seq
    START WITH 4
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE yulya.measurment_baths_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE yulya.measurment_input_params_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE yulya.measurment_types_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE yulya.military_ranks_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE yulya.employees_seq OWNER TO admin;
ALTER SEQUENCE yulya.measure_settings_seq OWNER TO admin;
ALTER SEQUENCE yulya.measurment_baths_seq OWNER TO admin;
ALTER SEQUENCE yulya.measurment_input_params_seq OWNER TO admin;
ALTER SEQUENCE yulya.measurment_types_seq OWNER TO admin;
ALTER SEQUENCE yulya.military_ranks_seq OWNER TO admin;

begin 
	
	alter table public.measurment_baths
	add constraint emploee_id_fk 
	foreign key (emploee_id)
	references public.employees (id);
	
	alter table public.measurment_baths
	add constraint measurment_input_param_id_fk 
	foreign key(measurment_input_param_id)
	references public.measurment_input_params(id);
	
	alter table public.measurment_input_params
	add constraint measurment_type_id_fk
	foreign key(measurment_type_id)
	references public.measurment_types (id);
	
	alter table public.employees
	add constraint military_rank_id_fk
	foreign key(military_rank_id)
	references public.military_ranks (id);

end;

-- select yulya."getDate"();
-- select yulya."getHeight"(10);
-- select * from yulya.new_data_type(10,700,23);
-- select yulya."getBBBTT"((25, 760, 45)::yulya.send_params);

end;
end $$;