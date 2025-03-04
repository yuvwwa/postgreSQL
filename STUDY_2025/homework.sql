--
-- PostgreSQL database dump
--

-- Dumped from database version 16.3 (Debian 16.3-1.pgdg120+1)
-- Dumped by pg_dump version 16.6

-- Started on 2025-03-03 11:11:41 UTC

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

--
-- TOC entry 4 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- TOC entry 3491 (class 0 OID 0)
-- Dependencies: 4
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 901 (class 1247 OID 19866)
-- Name: input_params; Type: TYPE; Schema: public; Owner: admin
--

CREATE TYPE public.input_params AS (
	height numeric(8,2),
	temperature numeric(8,2),
	pressure numeric(8,2),
	wind_direction numeric(8,2),
	wind_speed numeric(8,2),
	bullet_demolition_range numeric(8,2)
);


ALTER TYPE public.input_params OWNER TO admin;

--
-- TOC entry 904 (class 1247 OID 19869)
-- Name: check_result; Type: TYPE; Schema: public; Owner: admin
--

CREATE TYPE public.check_result AS (
	is_check boolean,
	error_message text,
	params public.input_params
);


ALTER TYPE public.check_result OWNER TO admin;

--
-- TOC entry 898 (class 1247 OID 19863)
-- Name: interpolation_type; Type: TYPE; Schema: public; Owner: admin
--

CREATE TYPE public.interpolation_type AS (
	x0 numeric(8,2),
	x1 numeric(8,2),
	y0 numeric(8,2),
	y1 numeric(8,2)
);


ALTER TYPE public.interpolation_type OWNER TO admin;

--
-- TOC entry 907 (class 1247 OID 19872)
-- Name: temperature_correction; Type: TYPE; Schema: public; Owner: admin
--

CREATE TYPE public.temperature_correction AS (
	calc_height_id integer,
	height integer,
	deviation integer
);


ALTER TYPE public.temperature_correction OWNER TO admin;

--
-- TOC entry 259 (class 1255 OID 19947)
-- Name: fn_calc_header_meteo_avg(public.input_params); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_calc_header_meteo_avg(par_params public.input_params) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
	var_result text;
	var_params input_params;
begin

	-- Проверяю аргументы
	var_params := public.fn_check_input_params(par_params);
	
	select
		-- Дата
		public.fn_calc_header_period(now()) ||
		--Высота расположения метеопоста над уровнем моря.
	    lpad( 340::text, 4, '0' ) ||
		-- Отклонение наземного давления атмосферы
		lpad(
				case when coalesce(var_params.pressure,0) < 0 then
					'5' 
				else ''
				end ||
				lpad ( abs(( coalesce(var_params.pressure, 0) )::int)::text,2,'0')
			, 3, '0') as "БББ",
		-- Отклонение приземной виртуальной температуры	
		lpad( 
				case when coalesce( var_params.temperature, 0) < 0 then
					'5'
				else
					''
				end ||
				( coalesce(var_params.temperature,0)::int)::text
			, 2,'0')
		into 	var_result;
	return 	var_result;

end;
$$;


ALTER FUNCTION public.fn_calc_header_meteo_avg(par_params public.input_params) OWNER TO admin;

--
-- TOC entry 252 (class 1255 OID 19939)
-- Name: fn_calc_header_period(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_calc_header_period(par_period timestamp with time zone) RETURNS text
    LANGUAGE sql
    RETURN ((((CASE WHEN (EXTRACT(day FROM par_period) < (10)::numeric) THEN '0'::text ELSE ''::text END || (EXTRACT(day FROM par_period))::text) || CASE WHEN (EXTRACT(hour FROM par_period) < (10)::numeric) THEN '0'::text ELSE ''::text END) || (EXTRACT(hour FROM par_period))::text) || "left"(CASE WHEN (EXTRACT(minute FROM par_period) < (10)::numeric) THEN '0'::text ELSE (EXTRACT(minute FROM par_period))::text END, 1));


ALTER FUNCTION public.fn_calc_header_period(par_period timestamp with time zone) OWNER TO admin;

--
-- TOC entry 239 (class 1255 OID 19940)
-- Name: fn_calc_header_pressure(numeric); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_calc_header_pressure(par_pressure numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare
	default_pressure numeric(8,2) default 750;
	table_pressure numeric(8,2) default null;
	default_pressure_key character varying default 'calc_table_pressure' ;
begin

	raise notice 'Расчет отклонения наземного давления для %', par_pressure;
	
	-- Определяем граничное табличное значение
	if not exists (select 1 from public.measurment_settings where key = default_pressure_key ) then
	Begin
		table_pressure :=  default_pressure;
	end;
	else
	begin
		select value::numeric(18,2) 
		into table_pressure
		from  public.measurment_settings where key = default_pressure_key;
	end;
	end if;

	
	-- Результат
	return par_pressure - coalesce(table_pressure,table_pressure) ;

end;
$$;


ALTER FUNCTION public.fn_calc_header_pressure(par_pressure numeric) OWNER TO admin;

--
-- TOC entry 251 (class 1255 OID 19938)
-- Name: fn_calc_header_temperature(numeric); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_calc_header_temperature(par_temperature numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
declare
	default_temperature numeric(8,2) default 15.9;
	default_temperature_key character varying default 'calc_table_temperature' ;
	virtual_temperature numeric(8,2) default 0;
	deltaTv numeric(8,2) default 0;
	var_result numeric(8,2) default 0;
begin	

	raise notice 'Расчет отклонения приземной виртуальной температуры по температуре %', par_temperature;

	-- Определим табличное значение температуры
	Select coalesce(value::numeric(8,2), default_temperature) 
	from public.measurment_settings 
	into virtual_temperature
	where 
		key = default_temperature_key;

    -- Вирутальная поправка
	deltaTv := par_temperature + 
		public.fn_calc_temperature_interpolation(par_temperature => par_temperature);
		
	-- Отклонение приземной виртуальной температуры
	var_result := deltaTv - virtual_temperature;
	
	return var_result;
end;
$$;


ALTER FUNCTION public.fn_calc_header_temperature(par_temperature numeric) OWNER TO admin;

--
-- TOC entry 255 (class 1255 OID 19943)
-- Name: fn_calc_temperature_interpolation(numeric); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_calc_temperature_interpolation(par_temperature numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
	-- Расчет интерполяции 
	declare 
			var_interpolation interpolation_type;
	        var_result numeric(8,2) default 0;
	        var_min_temparure numeric(8,2) default 0;
	        var_max_temperature numeric(8,2) default 0;
	        var_denominator numeric(8,2) default 0;
	begin

  				raise notice 'Расчет интерполяции для температуры %', par_temperature;

                -- Проверим, возможно температура совпадает со значением в справочнике
                if exists (select 1 from public.calc_temperature_correction where temperature = par_temperature ) then
                begin
                        select correction 
                        into  var_result 
                        from  public.calc_temperature_correction
                        where 
                                temperature = par_temperature;
                end;
                else    
                begin
                        -- Получим диапазон в котором работают поправки
                        select min(temperature), max(temperature) 
                        into var_min_temparure, var_max_temperature
                        from public.calc_temperature_correction;

                        if par_temperature < var_min_temparure or   
                           par_temperature > var_max_temperature then

                                raise exception 'Некорректно передан параметр! Невозможно рассчитать поправку. Значение должно укладываться в диаппазон: %, %',
                                        var_min_temparure, var_max_temperature;
                        end if;   

                        -- Получим граничные параметры

                        select x0, y0, x1, y1 
						 into var_interpolation.x0, var_interpolation.y0, var_interpolation.x1, var_interpolation.y1
                        from
                        (
                                select t1.temperature as x0, t1.correction as y0
                                from public.calc_temperature_correction as t1
                                where t1.temperature <= par_temperature
                                order by t1.temperature desc
                                limit 1
                        ) as leftPart
                        cross join
                        (
                                select t1.temperature as x1, t1.correction as y1
                                from public.calc_temperature_correction as t1
                                where t1.temperature >= par_temperature
                                order by t1.temperature 
                                limit 1
                        ) as rightPart;

                        raise notice 'Граничные значения %', var_interpolation;

                        -- Расчет поправки
                        var_denominator := var_interpolation.x1 - var_interpolation.x0;
                        if var_denominator = 0.0 then

                                raise exception 'Деление на нуль. Возможно, некорректные данные в таблице с поправками!';

                        end if;

						var_result := (par_temperature - var_interpolation.x0) * (var_interpolation.y1 - var_interpolation.y0) / var_denominator + var_interpolation.y0;

                end;
                end if;

				return var_result;

end;
$$;


ALTER FUNCTION public.fn_calc_temperature_interpolation(par_temperature numeric) OWNER TO admin;

--
-- TOC entry 254 (class 1255 OID 19942)
-- Name: fn_check_input_params(public.input_params); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_check_input_params(par_param public.input_params) RETURNS public.input_params
    LANGUAGE plpgsql
    AS $$
declare
	var_result check_result;
begin

	var_result := fn_check_input_params(
		par_param.height, par_param.temperature, par_param.pressure, par_param.wind_direction,
		par_param.wind_speed, par_param.bullet_demolition_range
	);

	if var_result.is_check = False then
		raise exception 'Ошибка %', var_result.error_message;
	end if;
	
	return var_result.params;
end ;
$$;


ALTER FUNCTION public.fn_check_input_params(par_param public.input_params) OWNER TO admin;

--
-- TOC entry 253 (class 1255 OID 19941)
-- Name: fn_check_input_params(numeric, numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_check_input_params(par_height numeric, par_temperature numeric, par_pressure numeric, par_wind_direction numeric, par_wind_speed numeric, par_bullet_demolition_range numeric) RETURNS public.check_result
    LANGUAGE plpgsql
    AS $$
declare
	var_result public.check_result;
begin
	var_result.is_check = False;
	
	-- Температура
	if not exists (
		select 1 from (
				select 
						coalesce(min_temperature , '0')::numeric(8,2) as min_temperature, 
						coalesce(max_temperature, '0')::numeric(8,2) as max_temperature
				from 
				(select 1 ) as t
					cross join
					( select value as  min_temperature from public.measurment_settings where key = 'min_temperature' ) as t1
					cross join 
					( select value as  max_temperature from public.measurment_settings where key = 'max_temperature' ) as t2
				) as t	
			where
				par_temperature between min_temperature and max_temperature
			) then

			var_result.error_message := format('Температура % не укладывает в диаппазон!', par_temperature);
	end if;

	var_result.params.temperature = par_temperature;

	
	-- Давление
	if not exists (
		select 1 from (
			select 
					coalesce(min_pressure , '0')::numeric(8,2) as min_pressure, 
					coalesce(max_pressure, '0')::numeric(8,2) as max_pressure
			from 
			(select 1 ) as t
				cross join
				( select value as  min_pressure from public.measurment_settings where key = 'min_pressure' ) as t1
				cross join 
				( select value as  max_pressure from public.measurment_settings where key = 'max_pressure' ) as t2
			) as t	
			where
				par_pressure between min_pressure and max_pressure
				) then

			var_result.error_message := format('Давление %s не укладывает в диаппазон!', par_pressure);
	end if;

	var_result.params.pressure = par_pressure;			

		-- Высота
		if not exists (
			select 1 from (
				select 
						coalesce(min_height , '0')::numeric(8,2) as min_height, 
						coalesce(max_height, '0')::numeric(8,2) as  max_height
				from 
				(select 1 ) as t
					cross join
					( select value as  min_height from public.measurment_settings where key = 'min_height' ) as t1
					cross join 
					( select value as  max_height from public.measurment_settings where key = 'max_height' ) as t2
				) as t	
				where
				par_height between min_height and max_height
				) then

				var_result.error_message := format('Высота  %s не укладывает в диаппазон!', par_height);
		end if;

		var_result.params.height = par_height;
		
		-- Напрвление ветра
		if not exists (
			select 1 from (	
				select 
						coalesce(min_wind_direction , '0')::numeric(8,2) as min_wind_direction, 
						coalesce(max_wind_direction, '0')::numeric(8,2) as max_wind_direction
				from 
				(select 1 ) as t
					cross join
					( select value as  min_wind_direction from public.measurment_settings where key = 'min_wind_direction' ) as t1
					cross join 
					( select value as  max_wind_direction from public.measurment_settings where key = 'max_wind_direction' ) as t2
			)
				where
					par_wind_direction between min_wind_direction and max_wind_direction
			) then

			var_result.error_message := format('Направление ветра %s не укладывает в диаппазон!', par_wind_direction);
	end if;
			
	var_result.params.wind_direction = par_wind_direction;	
	var_result.params.wind_speed = par_wind_speed;

	if coalesce(var_result.error_message,'') = ''  then
		var_result.is_check = True;
	end if;	

	return var_result;
	
end;
$$;


ALTER FUNCTION public.fn_check_input_params(par_height numeric, par_temperature numeric, par_pressure numeric, par_wind_direction numeric, par_wind_speed numeric, par_bullet_demolition_range numeric) OWNER TO admin;

--
-- TOC entry 258 (class 1255 OID 19946)
-- Name: fn_get_random_text(integer, text); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_get_random_text(par_length integer, par_list_of_chars text DEFAULT 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789'::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
    var_len_of_list integer default length(par_list_of_chars);
    var_position integer;
    var_result text = '';
	var_random_number integer;
	var_max_value integer;
	var_min_value integer;
begin

	var_min_value := 10;
	var_max_value := 50;
	
    for var_position in 1 .. par_length loop
        -- добавляем к строке случайный символ
	    var_random_number := fn_get_randon_integer(var_min_value, var_max_value );
        var_result := var_result || substr(par_list_of_chars,  var_random_number ,1);
    end loop;
	
    return var_result;
	
end;
$$;


ALTER FUNCTION public.fn_get_random_text(par_length integer, par_list_of_chars text) OWNER TO admin;

--
-- TOC entry 256 (class 1255 OID 19944)
-- Name: fn_get_random_timestamp(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_get_random_timestamp(par_min_value timestamp without time zone, par_max_value timestamp without time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
begin
	 return random() * (par_max_value - par_min_value) + par_min_value;
end;
$$;


ALTER FUNCTION public.fn_get_random_timestamp(par_min_value timestamp without time zone, par_max_value timestamp without time zone) OWNER TO admin;

--
-- TOC entry 257 (class 1255 OID 19945)
-- Name: fn_get_randon_integer(integer, integer); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.fn_get_randon_integer(par_min_value integer, par_max_value integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	return floor((par_max_value + 1 - par_min_value)*random())::integer + par_min_value;
end;
$$;


ALTER FUNCTION public.fn_get_randon_integer(par_min_value integer, par_max_value integer) OWNER TO admin;

--
-- TOC entry 238 (class 1255 OID 19802)
-- Name: sp_1(); Type: PROCEDURE; Schema: public; Owner: admin
--

CREATE PROCEDURE public.sp_1()
    LANGUAGE plpgsql
    AS $$begin
raise notice 'test';
end;$$;


ALTER PROCEDURE public.sp_1() OWNER TO admin;

--
-- TOC entry 260 (class 1255 OID 19948)
-- Name: sp_calc_temperature_deviation(numeric, integer, public.temperature_correction[]); Type: PROCEDURE; Schema: public; Owner: admin
--

CREATE PROCEDURE public.sp_calc_temperature_deviation(IN par_temperature_correction numeric, IN par_measurement_type_id integer, INOUT par_corrections public.temperature_correction[])
    LANGUAGE plpgsql
    AS $$
declare
	var_row record;
	var_index integer;
	var_header_correction integer[];
	var_right_index integer;
	var_left_index integer;
	var_header_index integer;
	var_deviation integer;
	var_table integer[];
	var_correction temperature_correction;
begin

-- Проверяем наличие данные в таблице
if not exists ( 
	
		select 1
			from public.calc_height_correction as t1
			inner join public.calc_temperature_height_correction as t2 
				on t2.calc_height_id = t1.id
			where 
					measurment_type_id = par_measurement_type_id

			) then
			
		raise exception 'Для расчета поправок к температуре не хватает данных!';
	
	end if;

	for var_row in 
			-- Запрос на выборку высот
			select t2.*, t1.height 
			from public.calc_height_correction as t1
			inner join public.calc_temperature_height_correction as t2 
				on t2.calc_height_id = t1.id
			where measurment_type_id = par_measurement_type_id
		loop
			-- Получаем индекс корректировки
			var_index := par_temperature_correction::integer;
			-- Получаем заголовок 
			var_header_correction := (select values from public.calc_header_correction
				where id = var_row.calc_temperature_header_id );

			-- Проверяем данные
			if array_length(var_header_correction, 1) = 0 then
				raise exception 'Невозможно произвести расчет по высоте % Некорректные исходные данные или настройки',  var_row.height;
			end if;

			if array_length(var_header_correction, 1) < var_index then
				raise exception 'Невозможно произвести расчет по высоте % Некорректные исходные данные или настройки',  var_row.height;
			end if;

			-- Получаем левый и правый индекс
			var_right_index := abs(var_index % 10);
			var_header_index := abs(var_index) - var_right_index;

			-- Определяем корретировки
			if par_temperature_correction >= 0 then
				var_table := var_row.positive_values;
			else
				var_table := var_row.negative_values;
			end if;

			if 	var_header_index = 0 then
				var_header_index := 1;
			end if;

			var_left_index := var_header_correction[ var_header_index];
			if var_left_index = 0 then
				var_left_index := 1;
			end if;	

			-- Поправка на высоту	
			var_deviation:= var_table[ var_left_index  ] + var_table[ var_right_index     ];
			
			raise notice 'Для высоты % получили следующую поправку %', var_row.height, var_deviation;

			var_correction.calc_height_id := var_row.calc_height_id;
			var_correction.height := var_row.height;
			var_correction.deviation := var_deviation;
			par_corrections := array_append(par_corrections, var_correction);
	end loop;

end;
$$;


ALTER PROCEDURE public.sp_calc_temperature_deviation(IN par_temperature_correction numeric, IN par_measurement_type_id integer, INOUT par_corrections public.temperature_correction[]) OWNER TO admin;

--
-- TOC entry 232 (class 1259 OID 19873)
-- Name: calc_header_correction_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.calc_header_correction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.calc_header_correction_seq OWNER TO admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 233 (class 1259 OID 19874)
-- Name: calc_header_correction; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.calc_header_correction (
    id integer DEFAULT nextval('public.calc_header_correction_seq'::regclass) NOT NULL,
    measurment_type_id integer NOT NULL,
    description text NOT NULL,
    "values" integer[] NOT NULL
);


ALTER TABLE public.calc_header_correction OWNER TO admin;

--
-- TOC entry 234 (class 1259 OID 19882)
-- Name: calc_height_correction_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.calc_height_correction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.calc_height_correction_seq OWNER TO admin;

--
-- TOC entry 235 (class 1259 OID 19883)
-- Name: calc_height_correction; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.calc_height_correction (
    id integer DEFAULT nextval('public.calc_height_correction_seq'::regclass) NOT NULL,
    height integer NOT NULL,
    measurment_type_id integer NOT NULL
);


ALTER TABLE public.calc_height_correction OWNER TO admin;

--
-- TOC entry 227 (class 1259 OID 19856)
-- Name: calc_temperature_correction; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.calc_temperature_correction (
    temperature numeric(8,2) NOT NULL,
    correction numeric(8,2) NOT NULL
);


ALTER TABLE public.calc_temperature_correction OWNER TO admin;

--
-- TOC entry 236 (class 1259 OID 19889)
-- Name: calc_temperature_height_correction_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.calc_temperature_height_correction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.calc_temperature_height_correction_seq OWNER TO admin;

--
-- TOC entry 237 (class 1259 OID 19890)
-- Name: calc_temperature_height_correction; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.calc_temperature_height_correction (
    id integer DEFAULT nextval('public.calc_temperature_height_correction_seq'::regclass) NOT NULL,
    calc_height_id integer NOT NULL,
    calc_temperature_header_id integer NOT NULL,
    positive_values numeric[],
    negative_values numeric[]
);


ALTER TABLE public.calc_temperature_height_correction OWNER TO admin;

--
-- TOC entry 215 (class 1259 OID 19722)
-- Name: calc_temperatures_correction; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.calc_temperatures_correction (
    temperature numeric(8,2) NOT NULL,
    correction numeric(8,2)
);


ALTER TABLE public.calc_temperatures_correction OWNER TO admin;

--
-- TOC entry 219 (class 1259 OID 19817)
-- Name: employees_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.employees_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employees_seq OWNER TO admin;

--
-- TOC entry 218 (class 1259 OID 19810)
-- Name: employees; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.employees (
    id integer DEFAULT nextval('public.employees_seq'::regclass) NOT NULL,
    name text,
    birthday timestamp without time zone,
    military_rank_id integer NOT NULL
);


ALTER TABLE public.employees OWNER TO admin;

--
-- TOC entry 225 (class 1259 OID 19847)
-- Name: measurment_baths_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.measurment_baths_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.measurment_baths_seq OWNER TO admin;

--
-- TOC entry 224 (class 1259 OID 19841)
-- Name: measurment_baths; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.measurment_baths (
    id integer DEFAULT nextval('public.measurment_baths_seq'::regclass) NOT NULL,
    emploee_id integer NOT NULL,
    measurment_input_param_id integer NOT NULL,
    started timestamp without time zone DEFAULT now()
);


ALTER TABLE public.measurment_baths OWNER TO admin;

--
-- TOC entry 223 (class 1259 OID 19839)
-- Name: measurment_input_params_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.measurment_input_params_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.measurment_input_params_seq OWNER TO admin;

--
-- TOC entry 222 (class 1259 OID 19828)
-- Name: measurment_input_params; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.measurment_input_params (
    id integer DEFAULT nextval('public.measurment_input_params_seq'::regclass) NOT NULL,
    measurment_type_id integer NOT NULL,
    height numeric(8,2) DEFAULT 0,
    temperature numeric(8,2) DEFAULT 0,
    pressure numeric(8,2) DEFAULT 0,
    wind_direction numeric(8,2) DEFAULT 0,
    wind_speed numeric(8,2) DEFAULT 0,
    bullet_demolition_range numeric(8,2) DEFAULT 0
);


ALTER TABLE public.measurment_input_params OWNER TO admin;

--
-- TOC entry 226 (class 1259 OID 19849)
-- Name: measurment_settings; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.measurment_settings (
    key character varying(100) NOT NULL,
    value character varying(255),
    description text
);


ALTER TABLE public.measurment_settings OWNER TO admin;

--
-- TOC entry 221 (class 1259 OID 19826)
-- Name: measurment_types_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.measurment_types_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.measurment_types_seq OWNER TO admin;

--
-- TOC entry 220 (class 1259 OID 19819)
-- Name: measurment_types; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.measurment_types (
    id integer DEFAULT nextval('public.measurment_types_seq'::regclass) NOT NULL,
    short_name character varying(50),
    description text
);


ALTER TABLE public.measurment_types OWNER TO admin;

--
-- TOC entry 217 (class 1259 OID 19808)
-- Name: military_ranks_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.military_ranks_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.military_ranks_seq OWNER TO admin;

--
-- TOC entry 216 (class 1259 OID 19803)
-- Name: military_ranks; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.military_ranks (
    id integer DEFAULT nextval('public.military_ranks_seq'::regclass) NOT NULL,
    description character varying(255)
);


ALTER TABLE public.military_ranks OWNER TO admin;

--
-- TOC entry 3481 (class 0 OID 19874)
-- Dependencies: 233
-- Data for Name: calc_header_correction; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.calc_header_correction (id, measurment_type_id, description, "values") FROM stdin;
1	1	Заголовок для Таблицы № 2 (ДМК)	{0,1,2,3,4,5,6,7,8,9,10,20,30,40,50}
2	2	Заголовок для Таблицы № 2 (ВР)	{0,1,2,3,4,5,6,7,8,9,10,20,30,40,50}
\.


--
-- TOC entry 3483 (class 0 OID 19883)
-- Dependencies: 235
-- Data for Name: calc_height_correction; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.calc_height_correction (id, height, measurment_type_id) FROM stdin;
1	200	1
2	400	1
3	800	1
4	1200	1
5	1600	1
6	2000	1
7	2400	1
8	3000	1
9	4000	1
10	200	2
11	400	2
12	800	2
13	1200	2
14	1600	2
15	2000	2
16	2400	2
17	3000	2
18	4000	2
\.


--
-- TOC entry 3479 (class 0 OID 19856)
-- Dependencies: 227
-- Data for Name: calc_temperature_correction; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.calc_temperature_correction (temperature, correction) FROM stdin;
0.00	0.50
5.00	0.50
10.00	1.00
20.00	1.00
25.00	2.00
30.00	3.50
40.00	4.50
\.


--
-- TOC entry 3485 (class 0 OID 19890)
-- Dependencies: 237
-- Data for Name: calc_temperature_height_correction; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.calc_temperature_height_correction (id, calc_height_id, calc_temperature_header_id, positive_values, negative_values) FROM stdin;
1	1	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-3,-4,-5,-6,-7,-8,-8,-9,-20,-29,-39,-49}
2	2	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-3,-4,-5,-6,-6,-7,-8,-9,-19,-29,-38,-48}
3	3	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-3,-4,-5,-6,-6,-7,-7,-8,-18,-28,-37,-46}
4	4	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-3,-4,-4,-5,-5,-6,-7,-8,-17,-26,-35,-44}
5	5	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-3,-3,-4,-4,-5,-6,-7,-7,-17,-25,-34,-42}
6	6	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-3,-3,-4,-4,-5,-6,-6,-7,-16,-24,-32,-40}
7	7	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-2,-3,-4,-4,-5,-5,-6,-7,-15,-23,-31,-38}
8	8	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-2,-3,-4,-4,-4,-5,-5,-6,-15,-22,-30,-37}
9	9	1	{1,2,3,4,5,6,7,8,9,10,20,30,30,30}	{-1,-2,-2,-3,-4,-4,-4,-4,-5,-6,-14,-20,-27,-34}
\.


--
-- TOC entry 3467 (class 0 OID 19722)
-- Dependencies: 215
-- Data for Name: calc_temperatures_correction; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.calc_temperatures_correction (temperature, correction) FROM stdin;
0.00	0.50
5.00	0.50
10.00	1.00
20.00	1.00
25.00	2.00
30.00	3.50
40.00	4.50
\.


--
-- TOC entry 3470 (class 0 OID 19810)
-- Dependencies: 218
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.employees (id, name, birthday, military_rank_id) FROM stdin;
1	Воловиков Александр Сергеевич	1978-06-24 00:00:00	2
2	ЧУПНСМмгРзмПЦИЧЦЙЦРаЛШкОж	1990-10-09 02:10:12.03467	2
3	НжпЦеоЩоЪйЭйжзРЯЛлиМнЫдон	1983-01-20 23:44:52.731136	1
4	гЮЛФнУКажЦФЫЬЛЧеЪоонеЦОбп	1987-12-27 15:56:52.516212	1
5	ниФйШёФПЛЙЙзНСижИЫгИнННмв	1999-12-08 06:30:28.057949	2
6	гкИгУеКаМЩжзМШЩЦмкзлФггФК	1983-11-24 14:36:20.347115	2
\.


--
-- TOC entry 3476 (class 0 OID 19841)
-- Dependencies: 224
-- Data for Name: measurment_baths; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.measurment_baths (id, emploee_id, measurment_input_param_id, started) FROM stdin;
1	1	1	2025-02-28 00:39:49.931212
2	2	2	2025-02-04 20:05:03.149174
3	2	3	2025-02-04 02:54:57.642577
4	2	4	2025-02-01 05:11:41.18632
5	2	5	2025-02-02 17:05:35.80669
6	2	6	2025-02-03 13:28:35.268476
7	2	7	2025-02-02 13:29:30.149299
8	2	8	2025-02-03 12:07:42.117707
9	2	9	2025-02-03 13:37:00.121549
10	2	10	2025-02-03 12:10:58.820332
11	2	11	2025-02-01 08:49:38.22944
12	2	12	2025-02-03 14:07:36.284543
13	2	13	2025-02-02 17:26:23.440699
14	2	14	2025-02-02 20:53:58.811877
15	2	15	2025-02-02 08:48:11.44414
16	2	16	2025-02-04 18:21:27.152437
17	2	17	2025-02-01 20:53:01.129858
18	2	18	2025-02-04 17:27:48.334655
19	2	19	2025-02-03 03:56:09.63553
20	2	20	2025-02-01 21:04:14.512955
21	2	21	2025-02-02 04:41:10.799395
22	2	22	2025-02-01 11:19:04.96082
23	2	23	2025-02-02 19:44:55.07495
24	2	24	2025-02-04 01:54:02.155854
25	2	25	2025-02-04 03:15:52.253008
26	2	26	2025-02-03 12:34:04.266929
27	2	27	2025-02-04 02:15:02.036944
28	2	28	2025-02-04 08:09:22.961586
29	2	29	2025-02-03 07:17:49.088863
30	2	30	2025-02-03 02:59:05.965272
31	2	31	2025-02-03 04:54:24.965706
32	2	32	2025-02-01 18:08:01.316892
33	2	33	2025-02-04 01:38:36.811126
34	2	34	2025-02-03 14:24:49.354132
35	2	35	2025-02-01 10:11:05.675369
36	2	36	2025-02-04 10:39:47.852096
37	2	37	2025-02-04 11:41:15.920699
38	2	38	2025-02-02 15:00:17.267935
39	2	39	2025-02-02 21:57:38.918418
40	2	40	2025-02-01 07:19:26.817935
41	2	41	2025-02-01 08:43:53.392031
42	2	42	2025-02-04 14:12:34.431288
43	2	43	2025-02-03 14:40:28.234604
44	2	44	2025-02-03 13:58:34.266965
45	2	45	2025-02-01 03:08:25.027945
46	2	46	2025-02-02 10:28:30.060601
47	2	47	2025-02-02 00:37:33.448049
48	2	48	2025-02-04 23:13:04.191923
49	2	49	2025-02-04 14:59:00.143221
50	2	50	2025-02-02 07:57:56.864559
51	2	51	2025-02-01 15:39:31.09746
52	2	52	2025-02-03 20:37:36.445883
53	2	53	2025-02-04 04:36:26.620504
54	2	54	2025-02-01 09:13:48.26811
55	2	55	2025-02-01 23:02:20.800179
56	2	56	2025-02-01 10:05:25.026654
57	2	57	2025-02-04 05:34:14.681113
58	2	58	2025-02-01 18:24:02.386982
59	2	59	2025-02-01 18:54:32.710458
60	2	60	2025-02-04 21:00:11.195155
61	2	61	2025-02-03 12:57:14.136494
62	2	62	2025-02-04 02:23:28.402248
63	2	63	2025-02-01 01:18:19.131002
64	2	64	2025-02-04 23:35:27.003798
65	2	65	2025-02-02 04:33:52.073507
66	2	66	2025-02-02 12:11:06.017769
67	2	67	2025-02-03 15:34:31.221126
68	2	68	2025-02-01 07:28:15.406575
69	2	69	2025-02-02 07:22:51.979976
70	2	70	2025-02-03 10:42:32.399639
71	2	71	2025-02-01 13:58:51.987533
72	2	72	2025-02-02 06:45:40.138353
73	2	73	2025-02-03 17:24:41.650378
74	2	74	2025-02-02 19:24:04.76159
75	2	75	2025-02-01 03:51:17.074928
76	2	76	2025-02-01 02:04:33.197775
77	2	77	2025-02-01 20:28:27.892183
78	2	78	2025-02-03 21:12:53.469143
79	2	79	2025-02-03 00:21:23.185248
80	2	80	2025-02-04 20:22:56.988697
81	2	81	2025-02-04 20:07:04.953311
82	2	82	2025-02-03 20:13:38.636586
83	2	83	2025-02-01 15:41:08.021093
84	2	84	2025-02-04 19:17:21.240359
85	2	85	2025-02-03 02:48:27.066456
86	2	86	2025-02-03 21:50:37.137838
87	2	87	2025-02-04 00:28:05.297166
88	2	88	2025-02-03 04:57:37.347582
89	2	89	2025-02-03 12:47:23.322092
90	2	90	2025-02-04 15:45:18.99751
91	2	91	2025-02-04 01:23:48.902683
92	2	92	2025-02-01 19:04:48.693426
93	2	93	2025-02-01 18:53:31.015447
94	2	94	2025-02-04 06:19:33.110928
95	2	95	2025-02-03 11:42:15.106528
96	2	96	2025-02-04 22:31:51.917713
97	2	97	2025-02-03 07:48:02.10883
98	2	98	2025-02-03 01:27:20.047274
99	2	99	2025-02-03 09:02:05.626631
100	2	100	2025-02-04 21:48:57.760749
101	2	101	2025-02-04 21:20:04.585118
102	3	102	2025-02-04 14:34:42.793114
103	3	103	2025-02-02 09:40:06.192748
104	3	104	2025-02-01 00:35:51.338953
105	3	105	2025-02-03 13:32:05.223295
106	3	106	2025-02-02 01:18:07.339105
107	3	107	2025-02-04 21:48:01.99812
108	3	108	2025-02-03 17:10:26.483501
109	3	109	2025-02-01 17:51:29.558707
110	3	110	2025-02-02 16:42:34.823562
111	3	111	2025-02-02 01:11:00.695614
112	3	112	2025-02-03 01:35:50.185239
113	3	113	2025-02-04 08:17:22.214798
114	3	114	2025-02-03 02:13:39.481217
115	3	115	2025-02-04 06:34:10.04002
116	3	116	2025-02-01 09:12:37.915787
117	3	117	2025-02-01 18:21:31.832475
118	3	118	2025-02-04 03:07:18.669961
119	3	119	2025-02-02 10:46:32.829114
120	3	120	2025-02-02 21:54:27.313462
121	3	121	2025-02-03 08:34:26.153515
122	3	122	2025-02-03 17:41:43.918565
123	3	123	2025-02-04 01:56:01.615794
124	3	124	2025-02-03 01:00:56.369791
125	3	125	2025-02-01 21:24:16.69795
126	3	126	2025-02-01 08:39:58.632352
127	3	127	2025-02-03 19:46:51.014477
128	3	128	2025-02-02 16:51:54.309457
129	3	129	2025-02-04 09:17:30.820701
130	3	130	2025-02-01 15:14:07.141155
131	3	131	2025-02-03 09:50:39.84152
132	3	132	2025-02-02 07:40:14.218755
133	3	133	2025-02-01 21:24:45.763436
134	3	134	2025-02-01 02:05:23.312757
135	3	135	2025-02-02 08:53:15.603447
136	3	136	2025-02-04 18:24:17.08231
137	3	137	2025-02-02 08:30:52.910913
138	3	138	2025-02-03 21:37:57.751312
139	3	139	2025-02-03 07:16:28.268139
140	3	140	2025-02-01 04:12:46.043518
141	3	141	2025-02-01 19:53:52.756278
142	3	142	2025-02-04 00:28:11.620598
143	3	143	2025-02-01 18:22:14.794204
144	3	144	2025-02-01 02:30:41.053815
145	3	145	2025-02-01 16:44:43.812104
146	3	146	2025-02-03 05:41:10.413211
147	3	147	2025-02-03 09:31:42.878812
148	3	148	2025-02-01 19:10:23.70277
149	3	149	2025-02-02 21:57:03.246257
150	3	150	2025-02-02 10:30:36.864784
151	3	151	2025-02-03 18:41:41.78933
152	3	152	2025-02-04 11:53:55.308971
153	3	153	2025-02-02 23:45:30.631661
154	3	154	2025-02-03 23:31:07.968512
155	3	155	2025-02-02 21:22:44.706782
156	3	156	2025-02-03 11:59:57.867173
157	3	157	2025-02-01 03:07:32.463545
158	3	158	2025-02-04 19:27:41.75109
159	3	159	2025-02-02 13:58:42.191634
160	3	160	2025-02-04 03:14:14.406161
161	3	161	2025-02-01 20:35:42.144249
162	3	162	2025-02-03 13:31:44.406048
163	3	163	2025-02-01 16:29:37.913651
164	3	164	2025-02-01 03:30:50.716065
165	3	165	2025-02-01 00:48:50.141065
166	3	166	2025-02-03 18:30:10.272709
167	3	167	2025-02-04 11:03:07.111743
168	3	168	2025-02-02 23:16:00.122945
169	3	169	2025-02-02 12:32:33.631278
170	3	170	2025-02-04 04:44:38.23933
171	3	171	2025-02-03 18:32:53.298114
172	3	172	2025-02-01 03:02:44.443112
173	3	173	2025-02-01 20:13:36.046176
174	3	174	2025-02-02 20:17:15.515557
175	3	175	2025-02-01 19:55:56.720088
176	3	176	2025-02-02 06:13:42.787421
177	3	177	2025-02-03 00:48:42.011101
178	3	178	2025-02-03 07:32:23.270178
179	3	179	2025-02-03 06:14:08.880438
180	3	180	2025-02-01 19:25:08.181181
181	3	181	2025-02-04 01:00:47.243048
182	3	182	2025-02-04 23:50:45.818821
183	3	183	2025-02-02 12:14:33.251791
184	3	184	2025-02-02 18:57:49.065176
185	3	185	2025-02-02 00:45:36.604911
186	3	186	2025-02-04 12:55:53.738509
187	3	187	2025-02-04 22:53:27.562316
188	3	188	2025-02-02 00:11:18.69822
189	3	189	2025-02-03 22:08:00.459366
190	3	190	2025-02-02 02:40:57.813783
191	3	191	2025-02-02 20:43:58.016108
192	3	192	2025-02-04 10:24:19.789647
193	3	193	2025-02-01 05:11:54.314551
194	3	194	2025-02-03 14:11:34.522316
195	3	195	2025-02-02 06:08:46.361409
196	3	196	2025-02-03 19:45:15.475853
197	3	197	2025-02-01 20:18:59.645079
198	3	198	2025-02-01 23:55:08.545231
199	3	199	2025-02-04 21:21:58.074804
200	3	200	2025-02-02 23:16:50.911527
201	3	201	2025-02-01 17:56:33.420454
202	4	202	2025-02-02 04:20:41.094686
203	4	203	2025-02-02 07:06:04.131839
204	4	204	2025-02-01 07:44:19.469409
205	4	205	2025-02-02 04:14:11.569895
206	4	206	2025-02-01 00:54:53.245753
207	4	207	2025-02-03 17:28:49.371577
208	4	208	2025-02-02 08:50:32.706885
209	4	209	2025-02-01 00:52:59.190097
210	4	210	2025-02-01 09:07:04.979737
211	4	211	2025-02-03 15:22:15.940677
212	4	212	2025-02-02 10:41:58.696025
213	4	213	2025-02-02 22:39:13.592796
214	4	214	2025-02-01 01:11:07.686163
215	4	215	2025-02-03 20:39:43.149057
216	4	216	2025-02-03 18:28:40.619445
217	4	217	2025-02-04 03:35:47.539247
218	4	218	2025-02-04 18:29:25.074331
219	4	219	2025-02-01 20:42:31.932513
220	4	220	2025-02-03 13:30:21.170847
221	4	221	2025-02-04 03:05:51.775546
222	4	222	2025-02-04 19:25:26.401632
223	4	223	2025-02-02 04:59:17.697745
224	4	224	2025-02-03 09:32:33.159736
225	4	225	2025-02-03 21:14:44.168214
226	4	226	2025-02-03 03:36:06.898818
227	4	227	2025-02-01 15:25:57.230985
228	4	228	2025-02-04 12:48:49.622053
229	4	229	2025-02-01 16:00:13.557191
230	4	230	2025-02-02 05:43:15.667833
231	4	231	2025-02-01 21:53:48.180698
232	4	232	2025-02-04 23:57:56.566797
233	4	233	2025-02-03 21:42:21.770446
234	4	234	2025-02-01 13:11:30.98701
235	4	235	2025-02-03 00:43:36.545054
236	4	236	2025-02-03 19:35:11.037722
237	4	237	2025-02-04 17:45:54.654195
238	4	238	2025-02-04 01:14:02.779576
239	4	239	2025-02-02 13:43:06.671699
240	4	240	2025-02-01 06:06:41.097354
241	4	241	2025-02-04 03:58:09.386097
242	4	242	2025-02-04 16:18:48.227207
243	4	243	2025-02-04 07:24:53.999811
244	4	244	2025-02-02 02:06:38.117711
245	4	245	2025-02-03 01:48:59.221299
246	4	246	2025-02-02 10:35:40.581048
247	4	247	2025-02-03 22:55:33.350025
248	4	248	2025-02-03 00:56:29.708292
249	4	249	2025-02-04 02:31:15.639341
250	4	250	2025-02-01 09:17:49.624345
251	4	251	2025-02-04 10:20:19.525321
252	4	252	2025-02-03 10:30:22.668954
253	4	253	2025-02-02 20:06:55.572789
254	4	254	2025-02-04 21:55:53.510307
255	4	255	2025-02-02 11:11:48.822939
256	4	256	2025-02-02 11:14:53.015452
257	4	257	2025-02-01 10:22:53.693946
258	4	258	2025-02-02 06:24:06.675483
259	4	259	2025-02-01 05:03:55.919741
260	4	260	2025-02-02 12:30:17.515161
261	4	261	2025-02-02 15:01:31.535428
262	4	262	2025-02-03 09:29:36.392207
263	4	263	2025-02-02 19:18:45.485909
264	4	264	2025-02-03 02:02:01.773985
265	4	265	2025-02-04 10:54:16.318011
266	4	266	2025-02-01 20:32:47.670136
267	4	267	2025-02-02 05:23:17.458214
268	4	268	2025-02-01 12:44:49.360147
269	4	269	2025-02-03 05:43:19.036431
270	4	270	2025-02-02 09:52:20.209819
271	4	271	2025-02-01 22:24:10.328093
272	4	272	2025-02-01 18:41:55.13995
273	4	273	2025-02-04 10:13:58.93759
274	4	274	2025-02-04 16:53:09.089622
275	4	275	2025-02-04 20:42:18.425891
276	4	276	2025-02-03 02:28:54.107655
277	4	277	2025-02-04 12:15:08.335128
278	4	278	2025-02-04 20:40:25.146284
279	4	279	2025-02-01 07:04:40.616986
280	4	280	2025-02-03 09:26:55.050491
281	4	281	2025-02-01 08:59:29.397612
282	4	282	2025-02-03 03:27:42.197614
283	4	283	2025-02-04 00:53:27.034412
284	4	284	2025-02-04 21:23:56.046412
285	4	285	2025-02-01 06:11:17.153214
286	4	286	2025-02-03 17:22:27.469767
287	4	287	2025-02-01 10:51:30.988523
288	4	288	2025-02-03 04:55:59.806215
289	4	289	2025-02-03 06:11:22.341077
290	4	290	2025-02-04 21:18:48.028729
291	4	291	2025-02-03 16:27:35.847165
292	4	292	2025-02-02 21:29:08.845595
293	4	293	2025-02-03 18:05:35.723108
294	4	294	2025-02-04 06:05:25.922017
295	4	295	2025-02-03 06:46:32.849469
296	4	296	2025-02-02 22:16:40.611889
297	4	297	2025-02-03 08:10:18.719461
298	4	298	2025-02-03 10:24:40.034857
299	4	299	2025-02-03 09:15:40.877083
300	4	300	2025-02-02 09:33:59.375799
301	4	301	2025-02-03 17:22:44.86115
302	5	302	2025-02-04 12:22:33.37836
303	5	303	2025-02-04 17:59:59.346109
304	5	304	2025-02-04 05:50:41.108638
305	5	305	2025-02-01 11:01:08.931575
306	5	306	2025-02-01 09:54:59.300606
307	5	307	2025-02-03 12:13:16.717664
308	5	308	2025-02-03 07:21:31.61007
309	5	309	2025-02-02 10:51:47.959639
310	5	310	2025-02-01 01:40:52.615789
311	5	311	2025-02-02 12:51:22.637704
312	5	312	2025-02-04 00:18:32.394925
313	5	313	2025-02-03 04:03:18.191358
314	5	314	2025-02-01 00:34:52.050304
315	5	315	2025-02-01 08:56:32.679448
316	5	316	2025-02-03 06:57:59.993647
317	5	317	2025-02-01 14:18:20.720714
318	5	318	2025-02-01 03:11:48.163773
319	5	319	2025-02-02 05:18:15.326125
320	5	320	2025-02-02 04:14:27.191668
321	5	321	2025-02-03 22:30:29.887113
322	5	322	2025-02-02 06:58:13.177339
323	5	323	2025-02-02 00:42:13.248458
324	5	324	2025-02-03 00:16:56.350838
325	5	325	2025-02-04 18:29:52.138414
326	5	326	2025-02-01 00:14:07.780519
327	5	327	2025-02-04 05:22:53.495312
328	5	328	2025-02-01 23:50:34.429379
329	5	329	2025-02-02 18:29:19.42177
330	5	330	2025-02-04 12:35:22.636745
331	5	331	2025-02-01 10:09:57.49355
332	5	332	2025-02-02 06:02:22.033313
333	5	333	2025-02-04 10:24:20.009746
334	5	334	2025-02-04 07:58:32.968849
335	5	335	2025-02-01 02:46:25.98853
336	5	336	2025-02-04 09:05:35.376312
337	5	337	2025-02-01 18:14:07.324206
338	5	338	2025-02-04 06:59:33.681348
339	5	339	2025-02-01 02:50:20.342095
340	5	340	2025-02-03 21:46:36.880015
341	5	341	2025-02-03 18:16:04.324862
342	5	342	2025-02-03 00:04:06.119703
343	5	343	2025-02-01 08:31:20.689959
344	5	344	2025-02-03 22:19:20.562955
345	5	345	2025-02-01 12:14:58.127643
346	5	346	2025-02-02 14:57:03.219032
347	5	347	2025-02-03 23:13:05.781751
348	5	348	2025-02-03 13:17:10.727361
349	5	349	2025-02-02 13:43:37.420256
350	5	350	2025-02-01 02:56:47.59198
351	5	351	2025-02-01 04:39:59.265082
352	5	352	2025-02-02 13:28:34.90332
353	5	353	2025-02-03 03:23:08.173932
354	5	354	2025-02-03 05:36:00.327534
355	5	355	2025-02-02 23:41:34.394046
356	5	356	2025-02-03 10:57:55.405996
357	5	357	2025-02-02 07:53:44.273896
358	5	358	2025-02-03 22:24:11.084279
359	5	359	2025-02-03 07:26:27.089645
360	5	360	2025-02-04 22:11:28.056168
361	5	361	2025-02-01 15:20:51.93546
362	5	362	2025-02-02 04:25:58.835421
363	5	363	2025-02-01 02:21:39.180847
364	5	364	2025-02-02 11:20:44.835808
365	5	365	2025-02-01 11:29:51.730799
366	5	366	2025-02-04 17:12:07.828413
367	5	367	2025-02-03 23:07:07.168448
368	5	368	2025-02-03 17:06:25.416433
369	5	369	2025-02-03 18:10:35.034015
370	5	370	2025-02-03 23:01:44.544264
371	5	371	2025-02-04 00:36:47.409964
372	5	372	2025-02-03 23:13:25.631365
373	5	373	2025-02-03 17:39:42.833224
374	5	374	2025-02-03 03:41:46.843127
375	5	375	2025-02-01 19:02:04.710908
376	5	376	2025-02-01 11:59:17.613176
377	5	377	2025-02-02 20:37:53.764595
378	5	378	2025-02-01 22:05:38.242756
379	5	379	2025-02-01 08:29:08.374075
380	5	380	2025-02-04 12:35:20.073844
381	5	381	2025-02-02 13:34:42.624186
382	5	382	2025-02-03 15:19:44.002128
383	5	383	2025-02-02 08:12:01.727537
384	5	384	2025-02-01 14:08:37.769942
385	5	385	2025-02-03 19:22:21.262805
386	5	386	2025-02-01 04:31:20.883348
387	5	387	2025-02-03 12:32:06.898604
388	5	388	2025-02-01 23:55:13.874028
389	5	389	2025-02-01 07:30:18.255122
390	5	390	2025-02-02 19:06:53.933491
391	5	391	2025-02-01 05:54:03.842563
392	5	392	2025-02-01 13:57:38.359816
393	5	393	2025-02-04 16:00:32.732774
394	5	394	2025-02-04 12:12:05.404497
395	5	395	2025-02-04 20:50:20.175158
396	5	396	2025-02-03 10:16:22.434987
397	5	397	2025-02-03 22:20:58.323167
398	5	398	2025-02-01 00:50:47.931401
399	5	399	2025-02-01 13:38:32.324495
400	5	400	2025-02-02 23:18:04.321081
401	5	401	2025-02-04 03:02:45.850306
402	6	402	2025-02-03 15:48:36.84602
403	6	403	2025-02-03 08:59:31.644613
404	6	404	2025-02-01 10:41:12.994289
405	6	405	2025-02-01 11:20:33.124748
406	6	406	2025-02-04 11:45:48.8455
407	6	407	2025-02-01 12:09:47.288916
408	6	408	2025-02-03 06:13:09.899866
409	6	409	2025-02-04 19:37:00.50368
410	6	410	2025-02-02 06:52:04.710591
411	6	411	2025-02-04 13:49:31.656356
412	6	412	2025-02-01 10:42:35.315995
413	6	413	2025-02-02 03:05:51.255854
414	6	414	2025-02-02 00:42:55.493686
415	6	415	2025-02-02 23:58:59.682224
416	6	416	2025-02-03 08:15:34.215645
417	6	417	2025-02-04 06:35:47.640254
418	6	418	2025-02-01 20:44:56.193365
419	6	419	2025-02-01 10:56:35.62001
420	6	420	2025-02-04 12:22:00.447304
421	6	421	2025-02-02 08:11:21.395804
422	6	422	2025-02-03 06:19:25.357221
423	6	423	2025-02-04 17:10:26.850441
424	6	424	2025-02-04 12:57:27.360353
425	6	425	2025-02-01 04:09:58.246388
426	6	426	2025-02-01 17:41:43.056307
427	6	427	2025-02-01 14:54:31.316319
428	6	428	2025-02-02 23:48:12.176772
429	6	429	2025-02-03 18:39:27.626797
430	6	430	2025-02-04 19:44:17.824611
431	6	431	2025-02-02 15:42:33.669287
432	6	432	2025-02-03 05:27:14.10268
433	6	433	2025-02-04 02:16:11.089255
434	6	434	2025-02-02 15:03:01.923949
435	6	435	2025-02-03 03:59:46.890323
436	6	436	2025-02-03 06:35:43.794027
437	6	437	2025-02-03 02:11:14.641838
438	6	438	2025-02-04 07:08:29.832601
439	6	439	2025-02-04 12:52:11.980766
440	6	440	2025-02-04 08:22:12.974622
441	6	441	2025-02-04 06:27:00.292266
442	6	442	2025-02-01 11:18:11.76839
443	6	443	2025-02-03 02:44:57.071332
444	6	444	2025-02-03 03:11:14.63782
445	6	445	2025-02-03 09:08:02.619319
446	6	446	2025-02-02 15:00:08.080581
447	6	447	2025-02-02 16:58:53.638101
448	6	448	2025-02-03 19:45:42.098151
449	6	449	2025-02-04 12:39:44.342686
450	6	450	2025-02-03 15:15:22.009584
451	6	451	2025-02-02 04:08:18.68545
452	6	452	2025-02-01 01:49:43.463256
453	6	453	2025-02-03 13:09:23.50075
454	6	454	2025-02-04 17:56:16.020332
455	6	455	2025-02-02 13:04:27.809436
456	6	456	2025-02-04 06:45:22.984249
457	6	457	2025-02-02 03:52:40.234455
458	6	458	2025-02-04 03:58:26.385931
459	6	459	2025-02-03 17:12:57.220834
460	6	460	2025-02-01 15:53:12.871691
461	6	461	2025-02-02 19:18:25.352789
462	6	462	2025-02-01 21:14:03.121337
463	6	463	2025-02-04 07:01:55.740955
464	6	464	2025-02-04 23:42:33.588193
465	6	465	2025-02-01 23:03:40.031914
466	6	466	2025-02-03 01:19:50.778171
467	6	467	2025-02-02 06:43:43.9093
468	6	468	2025-02-01 11:52:08.228508
469	6	469	2025-02-02 01:29:06.180043
470	6	470	2025-02-03 17:24:48.03495
471	6	471	2025-02-04 12:28:22.365683
472	6	472	2025-02-02 11:06:27.071147
473	6	473	2025-02-02 00:06:25.016649
474	6	474	2025-02-02 19:17:19.648174
475	6	475	2025-02-04 14:50:57.81978
476	6	476	2025-02-01 13:16:55.167866
477	6	477	2025-02-02 16:08:37.542507
478	6	478	2025-02-04 14:59:58.877179
479	6	479	2025-02-04 09:20:52.755266
480	6	480	2025-02-01 18:47:08.952887
481	6	481	2025-02-03 19:15:41.537613
482	6	482	2025-02-03 03:55:05.20365
483	6	483	2025-02-04 08:44:00.791122
484	6	484	2025-02-04 20:08:41.34868
485	6	485	2025-02-03 08:02:29.81686
486	6	486	2025-02-04 05:52:07.567255
487	6	487	2025-02-03 03:45:18.351444
488	6	488	2025-02-03 08:22:05.710081
489	6	489	2025-02-03 18:34:39.968078
490	6	490	2025-02-01 11:04:49.291545
491	6	491	2025-02-01 23:05:33.885101
492	6	492	2025-02-02 17:40:46.681403
493	6	493	2025-02-04 17:29:45.634493
494	6	494	2025-02-02 05:16:26.590185
495	6	495	2025-02-04 00:56:15.807365
496	6	496	2025-02-02 06:13:25.116659
497	6	497	2025-02-03 07:27:45.182607
498	6	498	2025-02-01 14:43:12.701278
499	6	499	2025-02-01 21:59:08.65569
500	6	500	2025-02-03 21:08:07.400241
501	6	501	2025-02-01 12:11:02.94796
\.


--
-- TOC entry 3474 (class 0 OID 19828)
-- Dependencies: 222
-- Data for Name: measurment_input_params; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.measurment_input_params (id, measurment_type_id, height, temperature, pressure, wind_direction, wind_speed, bullet_demolition_range) FROM stdin;
1	1	100.00	12.00	34.00	0.20	45.00	0.00
2	2	400.00	10.00	687.00	52.00	13.00	0.00
3	1	390.00	49.00	814.00	5.00	28.00	0.00
4	2	406.00	2.00	586.00	44.00	8.00	0.00
5	1	68.00	32.00	789.00	29.00	57.00	0.00
6	1	359.00	1.00	611.00	50.00	8.00	0.00
7	1	249.00	29.00	686.00	47.00	48.00	0.00
8	1	162.00	4.00	519.00	57.00	31.00	0.00
9	1	317.00	44.00	551.00	23.00	35.00	0.00
10	1	56.00	44.00	571.00	55.00	23.00	0.00
11	1	358.00	41.00	711.00	35.00	40.00	0.00
12	1	396.00	29.00	711.00	14.00	16.00	0.00
13	1	456.00	1.00	535.00	21.00	23.00	0.00
14	1	447.00	16.00	511.00	43.00	16.00	0.00
15	2	295.00	8.00	549.00	37.00	19.00	0.00
16	1	226.00	15.00	570.00	54.00	32.00	0.00
17	1	567.00	24.00	539.00	29.00	10.00	0.00
18	2	599.00	48.00	659.00	16.00	23.00	0.00
19	2	67.00	38.00	764.00	19.00	56.00	0.00
20	1	140.00	34.00	815.00	1.00	4.00	0.00
21	2	80.00	44.00	573.00	16.00	23.00	0.00
22	1	230.00	9.00	680.00	23.00	4.00	0.00
23	1	110.00	7.00	604.00	6.00	37.00	0.00
24	1	119.00	47.00	706.00	54.00	38.00	0.00
25	1	229.00	20.00	500.00	45.00	1.00	0.00
26	2	456.00	3.00	643.00	39.00	43.00	0.00
27	2	515.00	36.00	725.00	0.00	45.00	0.00
28	2	422.00	44.00	795.00	8.00	38.00	0.00
29	2	400.00	46.00	754.00	6.00	50.00	0.00
30	2	384.00	34.00	831.00	17.00	55.00	0.00
31	1	494.00	10.00	728.00	16.00	35.00	0.00
32	1	121.00	8.00	538.00	28.00	30.00	0.00
33	2	369.00	27.00	571.00	33.00	33.00	0.00
34	1	88.00	29.00	554.00	29.00	14.00	0.00
35	2	225.00	13.00	597.00	40.00	10.00	0.00
36	2	467.00	39.00	657.00	17.00	51.00	0.00
37	1	392.00	44.00	529.00	36.00	43.00	0.00
38	2	295.00	13.00	778.00	3.00	22.00	0.00
39	1	510.00	43.00	531.00	33.00	15.00	0.00
40	2	498.00	40.00	746.00	8.00	11.00	0.00
41	2	506.00	46.00	689.00	55.00	20.00	0.00
42	2	180.00	35.00	756.00	53.00	38.00	0.00
43	1	159.00	35.00	609.00	42.00	50.00	0.00
44	2	219.00	21.00	637.00	38.00	20.00	0.00
45	1	292.00	22.00	672.00	39.00	37.00	0.00
46	2	313.00	24.00	826.00	41.00	27.00	0.00
47	1	544.00	23.00	583.00	36.00	19.00	0.00
48	1	486.00	5.00	544.00	49.00	16.00	0.00
49	2	412.00	44.00	599.00	14.00	3.00	0.00
50	1	70.00	25.00	516.00	20.00	26.00	0.00
51	2	280.00	8.00	836.00	1.00	25.00	0.00
52	1	205.00	40.00	697.00	48.00	58.00	0.00
53	2	460.00	12.00	623.00	22.00	57.00	0.00
54	2	333.00	27.00	781.00	39.00	12.00	0.00
55	2	589.00	33.00	581.00	57.00	46.00	0.00
56	2	454.00	13.00	648.00	59.00	38.00	0.00
57	2	497.00	29.00	560.00	37.00	26.00	0.00
58	2	567.00	18.00	526.00	58.00	0.00	0.00
59	1	233.00	32.00	537.00	57.00	38.00	0.00
60	2	223.00	32.00	513.00	10.00	57.00	0.00
61	2	460.00	0.00	708.00	49.00	34.00	0.00
62	2	270.00	46.00	700.00	48.00	55.00	0.00
63	1	260.00	45.00	778.00	25.00	56.00	0.00
64	2	173.00	1.00	781.00	23.00	39.00	0.00
65	2	375.00	50.00	808.00	34.00	37.00	0.00
66	1	593.00	2.00	610.00	13.00	22.00	0.00
67	1	75.00	27.00	539.00	0.00	43.00	0.00
68	1	292.00	28.00	717.00	54.00	39.00	0.00
69	1	104.00	21.00	778.00	54.00	42.00	0.00
70	2	556.00	29.00	737.00	54.00	44.00	0.00
71	2	113.00	12.00	565.00	21.00	11.00	0.00
72	2	123.00	37.00	723.00	22.00	33.00	0.00
73	1	515.00	18.00	526.00	18.00	0.00	0.00
74	2	183.00	17.00	644.00	13.00	1.00	0.00
75	1	573.00	5.00	617.00	44.00	49.00	0.00
76	2	423.00	10.00	841.00	20.00	17.00	0.00
77	1	268.00	0.00	833.00	58.00	16.00	0.00
78	2	46.00	46.00	703.00	33.00	20.00	0.00
79	1	73.00	17.00	735.00	26.00	28.00	0.00
80	2	192.00	22.00	848.00	32.00	5.00	0.00
81	2	178.00	5.00	829.00	42.00	58.00	0.00
82	2	163.00	13.00	783.00	42.00	57.00	0.00
83	1	275.00	28.00	716.00	50.00	13.00	0.00
84	2	19.00	41.00	712.00	23.00	13.00	0.00
85	2	584.00	1.00	660.00	31.00	46.00	0.00
86	2	43.00	37.00	751.00	39.00	15.00	0.00
87	2	326.00	47.00	611.00	44.00	1.00	0.00
88	1	79.00	0.00	597.00	46.00	8.00	0.00
89	2	406.00	23.00	623.00	17.00	35.00	0.00
90	2	460.00	47.00	542.00	50.00	42.00	0.00
91	1	513.00	0.00	598.00	41.00	7.00	0.00
92	1	567.00	42.00	747.00	59.00	47.00	0.00
93	2	19.00	29.00	539.00	22.00	6.00	0.00
94	2	150.00	20.00	660.00	15.00	57.00	0.00
95	2	516.00	18.00	814.00	59.00	14.00	0.00
96	1	278.00	43.00	843.00	59.00	52.00	0.00
97	2	353.00	33.00	850.00	53.00	17.00	0.00
98	1	133.00	36.00	517.00	23.00	35.00	0.00
99	2	97.00	37.00	719.00	50.00	52.00	0.00
100	1	436.00	19.00	729.00	55.00	43.00	0.00
101	1	114.00	34.00	748.00	53.00	51.00	0.00
102	1	143.00	8.00	663.00	24.00	5.00	0.00
103	2	214.00	18.00	598.00	50.00	10.00	0.00
104	2	198.00	40.00	666.00	40.00	2.00	0.00
105	1	215.00	49.00	624.00	12.00	34.00	0.00
106	1	49.00	29.00	705.00	7.00	9.00	0.00
107	1	580.00	25.00	512.00	59.00	58.00	0.00
108	2	427.00	6.00	679.00	22.00	7.00	0.00
109	1	416.00	29.00	689.00	3.00	35.00	0.00
110	1	407.00	8.00	673.00	55.00	31.00	0.00
111	1	335.00	2.00	562.00	23.00	28.00	0.00
112	1	580.00	10.00	571.00	24.00	28.00	0.00
113	1	67.00	17.00	722.00	49.00	15.00	0.00
114	1	557.00	29.00	752.00	38.00	36.00	0.00
115	1	362.00	48.00	594.00	6.00	35.00	0.00
116	1	356.00	49.00	736.00	10.00	30.00	0.00
117	2	375.00	24.00	581.00	30.00	28.00	0.00
118	1	49.00	31.00	788.00	47.00	46.00	0.00
119	2	23.00	22.00	615.00	33.00	19.00	0.00
120	1	518.00	44.00	510.00	48.00	2.00	0.00
121	2	45.00	12.00	677.00	31.00	48.00	0.00
122	1	579.00	2.00	748.00	6.00	31.00	0.00
123	2	555.00	48.00	767.00	11.00	14.00	0.00
124	2	513.00	31.00	796.00	33.00	12.00	0.00
125	2	40.00	32.00	820.00	19.00	47.00	0.00
126	1	159.00	21.00	635.00	2.00	45.00	0.00
127	1	161.00	39.00	781.00	35.00	5.00	0.00
128	1	224.00	31.00	522.00	35.00	14.00	0.00
129	1	338.00	35.00	828.00	26.00	52.00	0.00
130	1	241.00	31.00	783.00	50.00	54.00	0.00
131	1	574.00	41.00	838.00	19.00	57.00	0.00
132	2	299.00	4.00	714.00	47.00	39.00	0.00
133	2	156.00	28.00	653.00	40.00	40.00	0.00
134	2	219.00	35.00	723.00	25.00	33.00	0.00
135	2	107.00	41.00	663.00	40.00	49.00	0.00
136	2	461.00	44.00	843.00	13.00	42.00	0.00
137	2	540.00	30.00	813.00	46.00	3.00	0.00
138	2	462.00	4.00	558.00	13.00	16.00	0.00
139	2	395.00	44.00	685.00	40.00	19.00	0.00
140	1	83.00	35.00	740.00	19.00	47.00	0.00
141	1	314.00	46.00	829.00	19.00	37.00	0.00
142	2	206.00	47.00	762.00	46.00	2.00	0.00
143	1	225.00	17.00	756.00	28.00	31.00	0.00
144	2	466.00	40.00	771.00	53.00	50.00	0.00
145	2	274.00	47.00	529.00	49.00	15.00	0.00
146	2	223.00	48.00	689.00	12.00	49.00	0.00
147	1	334.00	12.00	748.00	31.00	42.00	0.00
148	2	281.00	10.00	551.00	18.00	45.00	0.00
149	1	50.00	30.00	725.00	54.00	54.00	0.00
150	1	256.00	8.00	810.00	5.00	2.00	0.00
151	1	249.00	43.00	619.00	38.00	30.00	0.00
152	1	412.00	5.00	645.00	51.00	13.00	0.00
153	2	308.00	41.00	503.00	47.00	38.00	0.00
154	1	80.00	1.00	811.00	9.00	28.00	0.00
155	1	43.00	2.00	554.00	7.00	30.00	0.00
156	1	527.00	2.00	835.00	34.00	57.00	0.00
157	2	157.00	3.00	793.00	40.00	27.00	0.00
158	1	474.00	15.00	571.00	56.00	32.00	0.00
159	2	126.00	8.00	640.00	11.00	3.00	0.00
160	1	537.00	20.00	825.00	53.00	21.00	0.00
161	2	222.00	47.00	845.00	40.00	36.00	0.00
162	2	574.00	33.00	537.00	16.00	55.00	0.00
163	2	244.00	17.00	762.00	33.00	49.00	0.00
164	1	445.00	23.00	807.00	40.00	5.00	0.00
165	2	275.00	25.00	578.00	0.00	38.00	0.00
166	2	1.00	25.00	728.00	35.00	27.00	0.00
167	1	246.00	38.00	787.00	12.00	5.00	0.00
168	2	78.00	29.00	623.00	19.00	35.00	0.00
169	1	218.00	38.00	828.00	11.00	33.00	0.00
170	1	181.00	37.00	547.00	40.00	34.00	0.00
171	1	288.00	48.00	822.00	5.00	7.00	0.00
172	2	71.00	32.00	794.00	25.00	47.00	0.00
173	1	352.00	2.00	808.00	3.00	13.00	0.00
174	1	209.00	43.00	754.00	57.00	19.00	0.00
175	1	331.00	36.00	544.00	33.00	26.00	0.00
176	1	317.00	14.00	672.00	30.00	46.00	0.00
177	1	323.00	32.00	648.00	4.00	26.00	0.00
178	1	389.00	16.00	668.00	33.00	28.00	0.00
179	2	478.00	4.00	771.00	39.00	20.00	0.00
180	1	62.00	26.00	644.00	4.00	22.00	0.00
181	2	271.00	40.00	818.00	57.00	31.00	0.00
182	2	595.00	5.00	514.00	27.00	59.00	0.00
183	1	523.00	3.00	613.00	36.00	55.00	0.00
184	2	393.00	23.00	847.00	34.00	4.00	0.00
185	2	217.00	35.00	745.00	3.00	7.00	0.00
186	2	505.00	44.00	850.00	51.00	15.00	0.00
187	2	334.00	33.00	763.00	57.00	15.00	0.00
188	1	56.00	32.00	729.00	8.00	16.00	0.00
189	2	479.00	6.00	644.00	7.00	4.00	0.00
190	1	17.00	32.00	640.00	12.00	13.00	0.00
191	2	416.00	31.00	697.00	49.00	33.00	0.00
192	1	3.00	9.00	587.00	17.00	33.00	0.00
193	2	149.00	47.00	708.00	54.00	18.00	0.00
194	1	301.00	11.00	819.00	55.00	1.00	0.00
195	2	344.00	49.00	692.00	55.00	40.00	0.00
196	1	349.00	35.00	756.00	23.00	9.00	0.00
197	2	425.00	31.00	709.00	20.00	46.00	0.00
198	2	179.00	36.00	651.00	11.00	31.00	0.00
199	1	453.00	31.00	723.00	2.00	53.00	0.00
200	2	434.00	42.00	533.00	19.00	40.00	0.00
201	1	109.00	34.00	540.00	53.00	31.00	0.00
202	1	84.00	49.00	539.00	24.00	7.00	0.00
203	1	568.00	18.00	704.00	17.00	36.00	0.00
204	2	278.00	15.00	821.00	26.00	41.00	0.00
205	2	350.00	0.00	616.00	11.00	44.00	0.00
206	1	539.00	19.00	622.00	39.00	37.00	0.00
207	1	98.00	29.00	562.00	58.00	2.00	0.00
208	2	322.00	46.00	845.00	49.00	21.00	0.00
209	2	186.00	21.00	542.00	33.00	26.00	0.00
210	2	486.00	44.00	850.00	33.00	57.00	0.00
211	2	387.00	17.00	588.00	40.00	38.00	0.00
212	2	512.00	29.00	660.00	59.00	44.00	0.00
213	2	368.00	10.00	779.00	38.00	58.00	0.00
214	1	287.00	5.00	818.00	21.00	23.00	0.00
215	2	348.00	32.00	659.00	54.00	19.00	0.00
216	2	173.00	48.00	774.00	15.00	36.00	0.00
217	2	2.00	4.00	722.00	38.00	57.00	0.00
218	2	113.00	43.00	636.00	51.00	21.00	0.00
219	2	234.00	0.00	659.00	18.00	30.00	0.00
220	1	457.00	10.00	815.00	56.00	26.00	0.00
221	1	121.00	23.00	597.00	9.00	41.00	0.00
222	2	149.00	39.00	813.00	7.00	1.00	0.00
223	1	178.00	29.00	544.00	36.00	32.00	0.00
224	2	523.00	13.00	614.00	0.00	25.00	0.00
225	1	213.00	1.00	660.00	51.00	11.00	0.00
226	2	540.00	33.00	603.00	47.00	55.00	0.00
227	2	258.00	8.00	704.00	50.00	58.00	0.00
228	1	80.00	48.00	633.00	39.00	55.00	0.00
229	1	503.00	49.00	720.00	19.00	57.00	0.00
230	1	517.00	22.00	721.00	19.00	8.00	0.00
231	1	185.00	18.00	585.00	3.00	11.00	0.00
232	2	568.00	17.00	735.00	12.00	34.00	0.00
233	1	532.00	43.00	528.00	46.00	9.00	0.00
234	2	406.00	24.00	744.00	44.00	45.00	0.00
235	2	302.00	28.00	744.00	19.00	6.00	0.00
236	2	281.00	46.00	629.00	1.00	51.00	0.00
237	1	599.00	38.00	629.00	25.00	1.00	0.00
238	1	213.00	25.00	703.00	53.00	26.00	0.00
239	2	366.00	39.00	618.00	16.00	31.00	0.00
240	1	487.00	20.00	730.00	37.00	6.00	0.00
241	2	80.00	40.00	500.00	25.00	39.00	0.00
242	2	248.00	30.00	837.00	9.00	38.00	0.00
243	1	423.00	11.00	647.00	24.00	51.00	0.00
244	1	455.00	26.00	754.00	29.00	44.00	0.00
245	1	102.00	24.00	829.00	44.00	5.00	0.00
246	1	206.00	16.00	767.00	30.00	59.00	0.00
247	1	218.00	24.00	738.00	51.00	49.00	0.00
248	2	566.00	32.00	541.00	47.00	52.00	0.00
249	1	504.00	43.00	660.00	55.00	24.00	0.00
250	2	350.00	25.00	528.00	47.00	20.00	0.00
251	2	378.00	43.00	593.00	30.00	37.00	0.00
252	2	537.00	47.00	523.00	4.00	9.00	0.00
253	2	47.00	34.00	550.00	50.00	20.00	0.00
254	2	71.00	50.00	666.00	52.00	3.00	0.00
255	1	63.00	44.00	571.00	17.00	25.00	0.00
256	2	2.00	27.00	670.00	40.00	12.00	0.00
257	2	487.00	3.00	666.00	8.00	49.00	0.00
258	2	146.00	24.00	528.00	38.00	15.00	0.00
259	1	531.00	18.00	723.00	17.00	12.00	0.00
260	2	479.00	10.00	712.00	5.00	27.00	0.00
261	1	211.00	3.00	834.00	6.00	6.00	0.00
262	2	537.00	28.00	568.00	25.00	37.00	0.00
263	2	29.00	44.00	795.00	58.00	4.00	0.00
264	2	387.00	34.00	741.00	1.00	19.00	0.00
265	1	156.00	41.00	723.00	8.00	4.00	0.00
266	2	45.00	23.00	543.00	24.00	23.00	0.00
267	2	103.00	22.00	849.00	35.00	44.00	0.00
268	2	401.00	20.00	661.00	43.00	37.00	0.00
269	1	39.00	40.00	774.00	23.00	25.00	0.00
270	1	265.00	32.00	612.00	23.00	7.00	0.00
271	2	212.00	30.00	808.00	7.00	25.00	0.00
272	2	242.00	14.00	800.00	26.00	0.00	0.00
273	1	47.00	32.00	745.00	20.00	17.00	0.00
274	2	237.00	3.00	537.00	11.00	21.00	0.00
275	2	320.00	19.00	727.00	51.00	53.00	0.00
276	1	216.00	25.00	698.00	38.00	16.00	0.00
277	1	598.00	5.00	737.00	17.00	47.00	0.00
278	1	405.00	4.00	598.00	40.00	39.00	0.00
279	1	218.00	5.00	516.00	33.00	26.00	0.00
280	2	97.00	18.00	697.00	28.00	55.00	0.00
281	2	133.00	34.00	579.00	32.00	48.00	0.00
282	2	367.00	46.00	673.00	20.00	9.00	0.00
283	2	155.00	18.00	638.00	59.00	19.00	0.00
284	2	597.00	13.00	627.00	55.00	26.00	0.00
285	1	295.00	9.00	608.00	59.00	11.00	0.00
286	2	139.00	16.00	511.00	46.00	32.00	0.00
287	2	68.00	42.00	652.00	34.00	56.00	0.00
288	2	167.00	14.00	650.00	42.00	1.00	0.00
289	1	310.00	49.00	770.00	47.00	55.00	0.00
290	2	245.00	21.00	579.00	51.00	4.00	0.00
291	1	126.00	38.00	730.00	54.00	56.00	0.00
292	1	397.00	26.00	619.00	31.00	51.00	0.00
293	1	228.00	46.00	609.00	55.00	16.00	0.00
294	2	514.00	3.00	568.00	33.00	39.00	0.00
295	2	6.00	37.00	506.00	14.00	17.00	0.00
296	2	187.00	26.00	824.00	44.00	43.00	0.00
297	1	399.00	14.00	510.00	53.00	40.00	0.00
298	1	143.00	48.00	682.00	29.00	6.00	0.00
299	2	132.00	43.00	503.00	29.00	57.00	0.00
300	1	58.00	9.00	817.00	22.00	35.00	0.00
301	1	97.00	35.00	670.00	20.00	30.00	0.00
302	2	394.00	23.00	558.00	31.00	28.00	0.00
303	2	64.00	25.00	666.00	11.00	16.00	0.00
304	2	377.00	39.00	548.00	48.00	23.00	0.00
305	2	514.00	39.00	589.00	49.00	57.00	0.00
306	2	308.00	31.00	624.00	2.00	15.00	0.00
307	2	277.00	21.00	812.00	22.00	27.00	0.00
308	2	202.00	15.00	655.00	29.00	23.00	0.00
309	2	410.00	18.00	849.00	38.00	38.00	0.00
310	1	346.00	36.00	756.00	4.00	0.00	0.00
311	2	133.00	35.00	568.00	44.00	25.00	0.00
312	2	571.00	5.00	718.00	18.00	37.00	0.00
313	2	101.00	9.00	838.00	29.00	12.00	0.00
314	1	56.00	20.00	664.00	47.00	55.00	0.00
315	1	185.00	33.00	673.00	10.00	35.00	0.00
316	1	434.00	6.00	541.00	15.00	6.00	0.00
317	1	282.00	17.00	543.00	46.00	34.00	0.00
318	1	285.00	30.00	748.00	24.00	14.00	0.00
319	1	174.00	4.00	769.00	1.00	10.00	0.00
320	2	528.00	35.00	805.00	2.00	18.00	0.00
321	1	21.00	26.00	675.00	1.00	45.00	0.00
322	1	423.00	14.00	666.00	23.00	21.00	0.00
323	1	110.00	6.00	667.00	3.00	17.00	0.00
324	2	473.00	40.00	521.00	32.00	9.00	0.00
325	2	488.00	25.00	585.00	48.00	4.00	0.00
326	2	457.00	40.00	830.00	47.00	16.00	0.00
327	1	21.00	39.00	761.00	45.00	55.00	0.00
328	2	159.00	16.00	538.00	26.00	41.00	0.00
329	2	162.00	48.00	849.00	38.00	9.00	0.00
330	1	273.00	45.00	529.00	33.00	36.00	0.00
331	1	537.00	19.00	603.00	2.00	5.00	0.00
332	2	224.00	32.00	654.00	8.00	48.00	0.00
333	2	199.00	39.00	755.00	14.00	11.00	0.00
334	2	91.00	44.00	682.00	47.00	3.00	0.00
335	1	519.00	40.00	832.00	23.00	36.00	0.00
336	1	266.00	20.00	535.00	16.00	36.00	0.00
337	2	427.00	22.00	627.00	42.00	47.00	0.00
338	2	475.00	16.00	531.00	36.00	8.00	0.00
339	2	428.00	1.00	702.00	5.00	19.00	0.00
340	2	49.00	27.00	818.00	12.00	55.00	0.00
341	1	427.00	17.00	709.00	21.00	54.00	0.00
342	1	511.00	11.00	785.00	20.00	36.00	0.00
343	1	153.00	46.00	607.00	50.00	3.00	0.00
344	2	565.00	38.00	708.00	18.00	37.00	0.00
345	1	522.00	42.00	598.00	31.00	1.00	0.00
346	2	18.00	0.00	703.00	46.00	54.00	0.00
347	1	569.00	18.00	839.00	49.00	7.00	0.00
348	2	364.00	37.00	649.00	19.00	6.00	0.00
349	1	145.00	29.00	781.00	22.00	32.00	0.00
350	2	173.00	42.00	529.00	44.00	0.00	0.00
351	1	423.00	12.00	766.00	21.00	16.00	0.00
352	1	239.00	35.00	698.00	39.00	30.00	0.00
353	1	68.00	7.00	810.00	43.00	31.00	0.00
354	2	307.00	19.00	828.00	18.00	43.00	0.00
355	1	493.00	15.00	769.00	52.00	19.00	0.00
356	1	395.00	34.00	806.00	45.00	7.00	0.00
357	1	178.00	22.00	782.00	5.00	23.00	0.00
358	2	530.00	45.00	525.00	24.00	32.00	0.00
359	1	2.00	49.00	598.00	10.00	35.00	0.00
360	1	558.00	13.00	654.00	38.00	23.00	0.00
361	1	258.00	33.00	798.00	50.00	30.00	0.00
362	1	25.00	5.00	804.00	39.00	10.00	0.00
363	2	411.00	6.00	540.00	30.00	2.00	0.00
364	2	26.00	48.00	704.00	10.00	19.00	0.00
365	1	390.00	15.00	798.00	29.00	7.00	0.00
366	1	220.00	47.00	791.00	18.00	49.00	0.00
367	1	585.00	0.00	571.00	50.00	28.00	0.00
368	2	364.00	45.00	777.00	39.00	12.00	0.00
369	1	119.00	5.00	569.00	27.00	28.00	0.00
370	1	392.00	35.00	834.00	20.00	0.00	0.00
371	1	453.00	17.00	752.00	17.00	30.00	0.00
372	2	549.00	9.00	594.00	48.00	36.00	0.00
373	2	573.00	4.00	822.00	21.00	45.00	0.00
374	1	35.00	19.00	789.00	47.00	14.00	0.00
375	1	22.00	18.00	658.00	26.00	32.00	0.00
376	2	188.00	32.00	836.00	3.00	39.00	0.00
377	1	585.00	35.00	627.00	39.00	24.00	0.00
378	2	472.00	8.00	735.00	38.00	47.00	0.00
379	2	553.00	9.00	576.00	5.00	8.00	0.00
380	2	232.00	20.00	742.00	42.00	19.00	0.00
381	2	585.00	30.00	649.00	34.00	24.00	0.00
382	1	226.00	15.00	612.00	25.00	31.00	0.00
383	2	383.00	1.00	753.00	6.00	39.00	0.00
384	1	516.00	29.00	725.00	52.00	13.00	0.00
385	1	547.00	47.00	712.00	28.00	6.00	0.00
386	2	252.00	42.00	646.00	7.00	39.00	0.00
387	2	302.00	20.00	704.00	42.00	57.00	0.00
388	1	357.00	26.00	761.00	41.00	56.00	0.00
389	2	148.00	40.00	553.00	12.00	53.00	0.00
390	2	561.00	30.00	560.00	9.00	3.00	0.00
391	2	456.00	24.00	730.00	28.00	18.00	0.00
392	1	197.00	12.00	618.00	43.00	27.00	0.00
393	2	452.00	36.00	809.00	17.00	43.00	0.00
394	1	78.00	50.00	818.00	16.00	9.00	0.00
395	2	473.00	0.00	532.00	21.00	22.00	0.00
396	1	583.00	16.00	540.00	8.00	30.00	0.00
397	2	371.00	37.00	722.00	55.00	57.00	0.00
398	2	178.00	19.00	742.00	15.00	40.00	0.00
399	2	99.00	42.00	710.00	2.00	55.00	0.00
400	1	206.00	19.00	616.00	44.00	19.00	0.00
401	2	31.00	20.00	683.00	50.00	50.00	0.00
402	2	202.00	24.00	601.00	21.00	26.00	0.00
403	1	561.00	7.00	619.00	4.00	26.00	0.00
404	2	26.00	28.00	780.00	47.00	58.00	0.00
405	2	272.00	25.00	539.00	9.00	49.00	0.00
406	2	375.00	28.00	690.00	39.00	19.00	0.00
407	1	525.00	48.00	763.00	16.00	29.00	0.00
408	2	485.00	48.00	554.00	4.00	5.00	0.00
409	1	113.00	32.00	706.00	11.00	42.00	0.00
410	2	124.00	2.00	766.00	5.00	16.00	0.00
411	2	409.00	13.00	827.00	8.00	24.00	0.00
412	2	140.00	36.00	583.00	51.00	59.00	0.00
413	1	369.00	37.00	740.00	43.00	2.00	0.00
414	1	121.00	7.00	542.00	19.00	20.00	0.00
415	2	593.00	9.00	598.00	29.00	25.00	0.00
416	2	122.00	6.00	695.00	29.00	44.00	0.00
417	1	169.00	41.00	679.00	17.00	15.00	0.00
418	1	429.00	49.00	785.00	0.00	8.00	0.00
419	2	166.00	8.00	710.00	50.00	54.00	0.00
420	2	37.00	37.00	729.00	23.00	21.00	0.00
421	1	44.00	1.00	766.00	30.00	54.00	0.00
422	2	540.00	27.00	779.00	0.00	58.00	0.00
423	1	264.00	18.00	670.00	56.00	56.00	0.00
424	1	190.00	49.00	761.00	36.00	10.00	0.00
425	2	315.00	12.00	649.00	42.00	9.00	0.00
426	2	379.00	16.00	502.00	19.00	31.00	0.00
427	2	272.00	1.00	647.00	26.00	12.00	0.00
428	1	347.00	34.00	542.00	21.00	8.00	0.00
429	1	507.00	19.00	708.00	50.00	16.00	0.00
430	2	515.00	43.00	631.00	19.00	22.00	0.00
431	2	72.00	32.00	738.00	23.00	43.00	0.00
432	2	130.00	6.00	836.00	43.00	57.00	0.00
433	2	17.00	16.00	568.00	44.00	23.00	0.00
434	1	486.00	19.00	613.00	53.00	48.00	0.00
435	1	38.00	36.00	640.00	10.00	35.00	0.00
436	1	228.00	39.00	827.00	34.00	31.00	0.00
437	2	16.00	8.00	754.00	29.00	37.00	0.00
438	1	563.00	33.00	537.00	30.00	17.00	0.00
439	2	395.00	16.00	582.00	35.00	40.00	0.00
440	2	163.00	24.00	651.00	6.00	27.00	0.00
441	2	397.00	21.00	582.00	55.00	45.00	0.00
442	1	400.00	32.00	624.00	4.00	31.00	0.00
443	1	174.00	18.00	779.00	45.00	28.00	0.00
444	1	46.00	39.00	765.00	43.00	19.00	0.00
445	1	373.00	46.00	562.00	27.00	28.00	0.00
446	2	193.00	33.00	824.00	12.00	21.00	0.00
447	2	68.00	36.00	812.00	9.00	17.00	0.00
448	1	507.00	7.00	718.00	51.00	1.00	0.00
449	2	324.00	20.00	504.00	3.00	27.00	0.00
450	1	400.00	35.00	597.00	59.00	26.00	0.00
451	1	179.00	1.00	730.00	48.00	40.00	0.00
452	1	495.00	27.00	568.00	5.00	13.00	0.00
453	1	160.00	43.00	784.00	27.00	17.00	0.00
454	2	590.00	33.00	685.00	53.00	10.00	0.00
455	2	225.00	19.00	605.00	51.00	44.00	0.00
456	2	397.00	9.00	626.00	24.00	16.00	0.00
457	1	162.00	19.00	552.00	25.00	18.00	0.00
458	2	117.00	26.00	664.00	30.00	45.00	0.00
459	1	590.00	13.00	706.00	28.00	54.00	0.00
460	1	66.00	42.00	691.00	31.00	16.00	0.00
461	2	384.00	32.00	677.00	27.00	17.00	0.00
462	2	570.00	42.00	664.00	30.00	0.00	0.00
463	2	66.00	48.00	648.00	38.00	40.00	0.00
464	2	4.00	25.00	738.00	51.00	11.00	0.00
465	2	178.00	27.00	733.00	43.00	24.00	0.00
466	1	285.00	10.00	701.00	7.00	32.00	0.00
467	2	247.00	50.00	778.00	6.00	38.00	0.00
468	1	325.00	44.00	770.00	2.00	54.00	0.00
469	2	563.00	24.00	594.00	50.00	13.00	0.00
470	1	318.00	28.00	629.00	57.00	6.00	0.00
471	1	483.00	49.00	815.00	41.00	5.00	0.00
472	2	228.00	16.00	764.00	28.00	14.00	0.00
473	2	238.00	48.00	806.00	25.00	37.00	0.00
474	2	279.00	2.00	664.00	6.00	43.00	0.00
475	1	100.00	44.00	772.00	1.00	48.00	0.00
476	1	532.00	3.00	810.00	36.00	32.00	0.00
477	1	125.00	19.00	603.00	38.00	33.00	0.00
478	1	580.00	17.00	828.00	23.00	5.00	0.00
479	1	295.00	7.00	621.00	10.00	46.00	0.00
480	1	8.00	1.00	601.00	30.00	43.00	0.00
481	2	296.00	6.00	788.00	27.00	29.00	0.00
482	2	72.00	31.00	526.00	29.00	32.00	0.00
483	2	474.00	32.00	690.00	9.00	45.00	0.00
484	2	257.00	6.00	708.00	43.00	0.00	0.00
485	1	373.00	38.00	624.00	8.00	39.00	0.00
486	1	197.00	20.00	577.00	34.00	11.00	0.00
487	2	487.00	24.00	555.00	12.00	1.00	0.00
488	2	340.00	16.00	694.00	14.00	16.00	0.00
489	1	234.00	23.00	700.00	32.00	39.00	0.00
490	2	278.00	7.00	849.00	33.00	41.00	0.00
491	1	230.00	43.00	720.00	32.00	51.00	0.00
492	1	420.00	5.00	534.00	49.00	42.00	0.00
493	2	169.00	38.00	565.00	23.00	4.00	0.00
494	2	557.00	40.00	571.00	37.00	45.00	0.00
495	1	565.00	19.00	613.00	55.00	36.00	0.00
496	2	269.00	44.00	551.00	9.00	8.00	0.00
497	2	101.00	39.00	517.00	7.00	8.00	0.00
498	2	241.00	6.00	603.00	39.00	26.00	0.00
499	2	85.00	23.00	566.00	29.00	15.00	0.00
500	1	176.00	37.00	807.00	4.00	1.00	0.00
501	1	171.00	13.00	810.00	26.00	30.00	0.00
\.


--
-- TOC entry 3478 (class 0 OID 19849)
-- Dependencies: 226
-- Data for Name: measurment_settings; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.measurment_settings (key, value, description) FROM stdin;
min_temperature	-10	Минимальное значение температуры
max_temperature	50	Максимальное значение температуры
min_pressure	500	Минимальное значение давления
max_pressure	900	Максимальное значение давления
min_wind_direction	0	Минимальное значение направления ветра
max_wind_direction	59	Максимальное значение направления ветра
calc_table_temperature	15.9	Табличное значение температуры
calc_table_pressure	750	Табличное значение наземного давления
min_height	0	Минимальная высота
max_height	400	Максимальная высота
\.


--
-- TOC entry 3472 (class 0 OID 19819)
-- Dependencies: 220
-- Data for Name: measurment_types; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.measurment_types (id, short_name, description) FROM stdin;
1	ДМК	Десантный метео комплекс
2	ВР	Ветровое ружье
\.


--
-- TOC entry 3468 (class 0 OID 19803)
-- Dependencies: 216
-- Data for Name: military_ranks; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.military_ranks (id, description) FROM stdin;
1	Рядовой
2	Лейтенант
\.


--
-- TOC entry 3492 (class 0 OID 0)
-- Dependencies: 232
-- Name: calc_header_correction_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.calc_header_correction_seq', 2, true);


--
-- TOC entry 3493 (class 0 OID 0)
-- Dependencies: 234
-- Name: calc_height_correction_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.calc_height_correction_seq', 18, true);


--
-- TOC entry 3494 (class 0 OID 0)
-- Dependencies: 236
-- Name: calc_temperature_height_correction_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.calc_temperature_height_correction_seq', 9, true);


--
-- TOC entry 3495 (class 0 OID 0)
-- Dependencies: 219
-- Name: employees_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.employees_seq', 6, true);


--
-- TOC entry 3496 (class 0 OID 0)
-- Dependencies: 225
-- Name: measurment_baths_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.measurment_baths_seq', 501, true);


--
-- TOC entry 3497 (class 0 OID 0)
-- Dependencies: 223
-- Name: measurment_input_params_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.measurment_input_params_seq', 501, true);


--
-- TOC entry 3498 (class 0 OID 0)
-- Dependencies: 221
-- Name: measurment_types_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.measurment_types_seq', 3, false);


--
-- TOC entry 3499 (class 0 OID 0)
-- Dependencies: 217
-- Name: military_ranks_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.military_ranks_seq', 3, false);


--
-- TOC entry 3311 (class 2606 OID 19881)
-- Name: calc_header_correction calc_header_correction_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_header_correction
    ADD CONSTRAINT calc_header_correction_pkey PRIMARY KEY (id);


--
-- TOC entry 3313 (class 2606 OID 19888)
-- Name: calc_height_correction calc_height_correction_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_height_correction
    ADD CONSTRAINT calc_height_correction_pkey PRIMARY KEY (id);


--
-- TOC entry 3309 (class 2606 OID 19860)
-- Name: calc_temperature_correction calc_temperature_correction_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_temperature_correction
    ADD CONSTRAINT calc_temperature_correction_pkey PRIMARY KEY (temperature);


--
-- TOC entry 3315 (class 2606 OID 19897)
-- Name: calc_temperature_height_correction calc_temperature_height_correction_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_temperature_height_correction
    ADD CONSTRAINT calc_temperature_height_correction_pkey PRIMARY KEY (id);


--
-- TOC entry 3294 (class 2606 OID 19726)
-- Name: calc_temperatures_correction calc_temperatures_correction_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_temperatures_correction
    ADD CONSTRAINT calc_temperatures_correction_pkey PRIMARY KEY (temperature);


--
-- TOC entry 3298 (class 2606 OID 19816)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- TOC entry 3305 (class 2606 OID 19846)
-- Name: measurment_baths measurment_baths_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_baths
    ADD CONSTRAINT measurment_baths_pkey PRIMARY KEY (id);


--
-- TOC entry 3302 (class 2606 OID 19838)
-- Name: measurment_input_params measurment_input_params_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_input_params
    ADD CONSTRAINT measurment_input_params_pkey PRIMARY KEY (id);


--
-- TOC entry 3307 (class 2606 OID 19855)
-- Name: measurment_settings measurment_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_settings
    ADD CONSTRAINT measurment_settings_pkey PRIMARY KEY (key);


--
-- TOC entry 3300 (class 2606 OID 19825)
-- Name: measurment_types measurment_types_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_types
    ADD CONSTRAINT measurment_types_pkey PRIMARY KEY (id);


--
-- TOC entry 3296 (class 2606 OID 19807)
-- Name: military_ranks military_ranks_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.military_ranks
    ADD CONSTRAINT military_ranks_pkey PRIMARY KEY (id);


--
-- TOC entry 3303 (class 1259 OID 19954)
-- Name: ix_measurment_baths_emploee_id; Type: INDEX; Schema: public; Owner: admin
--

CREATE INDEX ix_measurment_baths_emploee_id ON public.measurment_baths USING btree (emploee_id);


--
-- TOC entry 3322 (class 2606 OID 19913)
-- Name: calc_temperature_height_correction calc_height_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_temperature_height_correction
    ADD CONSTRAINT calc_height_id_fk FOREIGN KEY (calc_height_id) REFERENCES public.calc_height_correction(id);


--
-- TOC entry 3323 (class 2606 OID 19908)
-- Name: calc_temperature_height_correction calc_temperature_header_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_temperature_height_correction
    ADD CONSTRAINT calc_temperature_header_id_fk FOREIGN KEY (calc_temperature_header_id) REFERENCES public.calc_temperature_height_correction(id);


--
-- TOC entry 3318 (class 2606 OID 19918)
-- Name: measurment_baths emploee_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_baths
    ADD CONSTRAINT emploee_id_fk FOREIGN KEY (emploee_id) REFERENCES public.employees(id);


--
-- TOC entry 3319 (class 2606 OID 19923)
-- Name: measurment_baths measurment_input_param_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_baths
    ADD CONSTRAINT measurment_input_param_id_fk FOREIGN KEY (measurment_input_param_id) REFERENCES public.measurment_input_params(id);


--
-- TOC entry 3320 (class 2606 OID 19898)
-- Name: calc_header_correction measurment_type_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_header_correction
    ADD CONSTRAINT measurment_type_id_fk FOREIGN KEY (measurment_type_id) REFERENCES public.measurment_types(id);


--
-- TOC entry 3321 (class 2606 OID 19903)
-- Name: calc_height_correction measurment_type_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.calc_height_correction
    ADD CONSTRAINT measurment_type_id_fk FOREIGN KEY (measurment_type_id) REFERENCES public.measurment_types(id);


--
-- TOC entry 3317 (class 2606 OID 19928)
-- Name: measurment_input_params measurment_type_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.measurment_input_params
    ADD CONSTRAINT measurment_type_id_fk FOREIGN KEY (measurment_type_id) REFERENCES public.measurment_types(id);


--
-- TOC entry 3316 (class 2606 OID 19933)
-- Name: employees military_rank_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT military_rank_id_fk FOREIGN KEY (military_rank_id) REFERENCES public.military_ranks(id);


-- Completed on 2025-03-03 11:11:41 UTC

--
-- PostgreSQL database dump complete
--

