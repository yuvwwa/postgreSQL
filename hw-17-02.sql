SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP SCHEMA IF EXISTS yulya CASCADE;
DROP FUNCTION IF EXISTS yulya."fnHeaderGetPressure"();
DROP FUNCTION IF EXISTS yulya."fnHeaderGetPressure"(pressure numeric);
DROP FUNCTION IF EXISTS yulya."getDate"();
DROP FUNCTION IF EXISTS yulya."getHeight"(height integer);
DROP FUNCTION IF EXISTS yulya."getBBBTT"(measurement_id integer);
DROP FUNCTION IF EXISTS yulya.interpolation();
DROP FUNCTION IF EXISTS yulya.interpolation(temp numeric);
DROP FUNCTION IF EXISTS yulya.new_data_type(temp numeric, pres numeric, wind numeric);
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
CREATE FUNCTION yulya."fnHeaderGetPressure"() RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare
	var_result numeric;
begin
	return yulya."fnHeaderGetPressure"();
end;
$$;

CREATE FUNCTION yulya."fnHeaderGetPressure"(pressure numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare
	var_result numeric;
begin
	var_result:=1 + pressure;
	return var_result;
end;
$$;


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
CREATE FUNCTION yulya."getBBBTT"(measurement_id integer) 
	RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	measure_temp numeric(8,2);
	measure_pres numeric(8,2);
	delta_temp integer;
	delta_pres integer;
	BBB text;
	TT text;
	var_result text;
begin

	select pressure into measure_pres from yulya.measurment_input_params where id = measurement_id;
	select temperature into measure_temp from yulya.measurment_input_params where id = measurement_id;

	delta_pres := measure_pres - 750;

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

	delta_temp := measure_temp;

	TT := case
		when length(abs(delta_temp)::text)=1 then '0' ||abs(delta_temp)
		else abs(delta_temp)::text
	end;

	var_result := BBB || TT;

	return var_result;
end;
$$;

-- Интерполяция (взяла на паре у Маши)
CREATE FUNCTION yulya.interpolation() RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare
	var_interpolation record;
 	var_result numeric(8,2) := 0;
	var_min_temparure numeric(8,2);
	var_max_temperature numeric(8,2);
	var_denominator numeric(8,2);
begin
  RAISE NOTICE 'Расчет интерполяции для температуры %', p_temperature;

  -- Проверим, возможно температура совпадает со значением в справочнике
  IF EXISTS (SELECT 1 FROM yulya.calc_temperatures_correction WHERE temperature = p_temperature) THEN
    SELECT correction INTO var_result FROM yulya.calc_temperatures_correction WHERE temperature = p_temperature;
  ELSE
    -- Получим диапазон в котором работают поправки
    SELECT min(temperature), max(temperature) INTO var_min_temparure, var_max_temperature
    FROM yulya.calc_temperatures_correction;

    IF p_temperature < var_min_temparure OR p_temperature > var_max_temperature THEN
      RAISE EXCEPTION 'Некорректно передан параметр! Невозможно рассчитать поправку. Значение должно укладываться в диаппазон: %, %',
                       var_min_temparure, var_max_temperature;
    END IF;

    -- Получим граничные параметры
    SELECT x0, y0, x1, y1
    INTO var_interpolation.x0, var_interpolation.y0, var_interpolation.x1, var_interpolation.y1
    FROM (
      SELECT t1.temperature AS x0, t1.correction AS y0
      FROM yulya.calc_temperatures_correction AS t1
      WHERE t1.temperature <= p_temperature
      ORDER BY t1.temperature DESC
      LIMIT 1
    ) AS leftPart
    CROSS JOIN (
      SELECT t1.temperature AS x1, t1.correction AS y1
      FROM yulya.calc_temperatures_correction AS t1
      WHERE t1.temperature >= p_temperature
      ORDER BY t1.temperature
      LIMIT 1
    ) AS rightPart;

    RAISE NOTICE 'Граничные значения %', var_interpolation;

    -- Расчет поправки
    var_denominator := var_interpolation.x1 - var_interpolation.x0;
    IF var_denominator = 0.0 THEN
      RAISE EXCEPTION 'Деление на нуль. Возможно, некорректные данные в таблице с поправками!';
    END IF;

    var_result := (p_temperature - var_interpolation.x0)*(var_interpolation.y1 - var_interpolation.y0) / var_denominator + var_interpolation.y0;
  END IF;

  RAISE NOTICE 'Результат: %', var_result;
  RETURN var_result;
end;
$$;

CREATE FUNCTION yulya.interpolation(temp numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    lower_temp DECIMAL;
    upper_temp DECIMAL;
    lower_corr DECIMAL;
    upper_corr DECIMAL;
    correction DECIMAL;
BEGIN
    -- Получаем нижнюю границу диапазона
    SELECT temperature, correction INTO lower_temp, lower_corr
    FROM temperature_corrections
    WHERE temperature <= temp
    ORDER BY temperature DESC
    LIMIT 1;

    -- Получаем верхнюю границу диапазона
    SELECT temperature, correction INTO upper_temp, upper_corr
    FROM temperature_corrections
    WHERE temperature >= temp
    ORDER BY temperature ASC
    LIMIT 1;

    -- Если температура ниже минимальной, вернуть первую поправку
    IF lower_temp IS NULL THEN
        RETURN upper_corr;
    END IF;

    -- Если температура выше максимальной, вернуть последнюю поправку
    IF upper_temp IS NULL THEN
        RETURN lower_corr;
    END IF;

    -- Если температура совпадает с одной из точек, вернуть точное значение
    IF temp = lower_temp THEN
        RETURN lower_corr;
    ELSIF temp = upper_temp THEN
        RETURN upper_corr;
    ELSE
        -- Линейная интерполяция между соседними значениями
        correction := lower_corr + (upper_corr - lower_corr) * (temp - lower_temp) / (upper_temp - lower_temp);
        RETURN correction;
    END IF;
END;
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
ALTER FUNCTION yulya.interpolation() OWNER TO admin;
ALTER FUNCTION yulya.interpolation(temp numeric) OWNER TO admin;
ALTER FUNCTION yulya.new_data_type(temp numeric, pres numeric, wind numeric) OWNER TO admin;
ALTER FUNCTION yulya."getBBBTT"(measurement_id integer) OWNER TO admin;

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

INSERT INTO yulya.measure_settings (id, measure_name, min_value, max_value, measure_unit) VALUES
    (1, 'temperature', -58.00, 58.00, 'Celsius'),
    (2, 'pressure', 500.00, 900.00, 'мм рт ст'),
    (3, 'wind_direction', 0.00, 59.00, 'degrees');


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

select yulya."getDate"();
select yulya."getHeight"(10);
select yulya."getBBBTT"(1);
select * from yulya.new_data_type(10,700,23);
