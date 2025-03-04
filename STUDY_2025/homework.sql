drop function if exists public.fn_calc_header_meteo_avg(par_params public.input_params);
drop function if exists public.fn_calc_header_period(par_period timestamp with time zone);
drop function if exists public.fn_calc_header_pressure(par_pressure numeric);
drop function if exists public.fn_calc_header_temperature(par_temperature numeric);
drop function if exists public.fn_calc_temperature_interpolation(par_temperature numeric);
drop function if exists public.fn_check_input_params(par_param public.input_params);
drop function if exists public.fn_check_input_params(par_height numeric, par_temperature numeric, par_pressure numeric, par_wind_direction numeric, par_wind_speed numeric, par_bullet_demolition_range numeric);
drop function if exists public.fn_get_random_text(par_length integer, par_list_of_chars text);
drop function if exists public.fn_get_random_timestamp(par_min_value timestamp without time zone, par_max_value timestamp without time zone);
drop function if exists public.fn_get_randon_integer(par_min_value integer, par_max_value integer);
drop procedure if exists public.sp_1();
drop procedure if exists public.sp_calc_temperature_deviation(IN par_temperature_correction numeric, IN par_measurement_type_id integer, INOUT par_corrections public.temperature_correction[]);
drop table if exists public.calc_header_correction;
drop table if exists public.calc_height_correction;
drop table if exists public.calc_temperature_correction;
drop table if exists public.calc_temperature_height_correction;
drop table if exists public.calc_temperatures_correction;
drop table if exists public.employees;
drop table if exists public.measurment_baths;
drop table if exists public.measurment_input_params;
drop table if exists public.measurment_settings;
drop table if exists public.calc_temperatures_correction;
drop table if exists public.measurment_types;
drop table if exists public.military_ranks;
drop sequence if exists public.calc_header_correction_seq;
drop sequence if exists public.calc_height_correction_seq;
drop sequence if exists public.calc_temperature_height_correction_seq;
drop sequence if exists public.employees_seq;
drop sequence if exists public.measurment_baths_seq;
drop sequence if exists public.measurment_input_params_seq;
drop sequence if exists public.measurment_types_seq;
drop sequence if exists public.military_ranks_seq;
drop type if exists public.check_result;
drop type if exists public.interpolation_type;
drop type if exists public.temperature_correction;
drop type if exists public.input_params;
drop schema if exists public;

CREATE SCHEMA public;

CREATE TYPE public.input_params AS (
	height numeric(8,2),
	temperature numeric(8,2),
	pressure numeric(8,2),
	wind_direction numeric(8,2),
	wind_speed numeric(8,2),
	bullet_demolition_range numeric(8,2)
);

CREATE TYPE public.check_result AS (
	is_check boolean,
	error_message text,
	params public.input_params
);

CREATE TYPE public.interpolation_type AS (
	x0 numeric(8,2),
	x1 numeric(8,2),
	y0 numeric(8,2),
	y1 numeric(8,2)
);

CREATE TYPE public.temperature_correction AS (
	calc_height_id integer,
	height integer,
	deviation integer
);

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

CREATE FUNCTION public.fn_calc_header_period(par_period timestamp with time zone) RETURNS text
    LANGUAGE sql
    RETURN ((((CASE WHEN (EXTRACT(day FROM par_period) < (10)::numeric) THEN '0'::text ELSE ''::text END || (EXTRACT(day FROM par_period))::text) || CASE WHEN (EXTRACT(hour FROM par_period) < (10)::numeric) THEN '0'::text ELSE ''::text END) || (EXTRACT(hour FROM par_period))::text) || "left"(CASE WHEN (EXTRACT(minute FROM par_period) < (10)::numeric) THEN '0'::text ELSE (EXTRACT(minute FROM par_period))::text END, 1));

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

CREATE FUNCTION public.fn_get_random_timestamp(par_min_value timestamp without time zone, par_max_value timestamp without time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
begin
	 return random() * (par_max_value - par_min_value) + par_min_value;
end;
$$;

CREATE FUNCTION public.fn_get_randon_integer(par_min_value integer, par_max_value integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
	return floor((par_max_value + 1 - par_min_value)*random())::integer + par_min_value;
end;
$$;

CREATE PROCEDURE public.sp_1()
    LANGUAGE plpgsql
    AS $$begin
raise notice 'test';
end;$$;

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

CREATE SEQUENCE public.calc_header_correction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.calc_header_correction (
    id integer DEFAULT nextval('public.calc_header_correction_seq'::regclass) NOT NULL,
    measurment_type_id integer NOT NULL,
    description text NOT NULL,
    "values" integer[] NOT NULL
);

CREATE SEQUENCE public.calc_height_correction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.calc_height_correction (
    id integer DEFAULT nextval('public.calc_height_correction_seq'::regclass) NOT NULL,
    height integer NOT NULL,
    measurment_type_id integer NOT NULL
);

CREATE TABLE public.calc_temperature_correction (
    temperature numeric(8,2) NOT NULL,
    correction numeric(8,2) NOT NULL
);

CREATE SEQUENCE public.calc_temperature_height_correction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.calc_temperature_height_correction (
    id integer DEFAULT nextval('public.calc_temperature_height_correction_seq'::regclass) NOT NULL,
    calc_height_id integer NOT NULL,
    calc_temperature_header_id integer NOT NULL,
    positive_values numeric[],
    negative_values numeric[]
);

CREATE TABLE public.calc_temperatures_correction (
    temperature numeric(8,2) NOT NULL,
    correction numeric(8,2)
);

CREATE SEQUENCE public.employees_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.employees (
    id integer DEFAULT nextval('public.employees_seq'::regclass) NOT NULL,
    name text,
    birthday timestamp without time zone,
    military_rank_id integer NOT NULL
);

CREATE SEQUENCE public.measurment_baths_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.measurment_baths (
    id integer DEFAULT nextval('public.measurment_baths_seq'::regclass) NOT NULL,
    emploee_id integer NOT NULL,
    measurment_input_param_id integer NOT NULL,
    started timestamp without time zone DEFAULT now()
);

CREATE SEQUENCE public.measurment_input_params_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

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

CREATE TABLE public.measurment_settings (
    key character varying(100) NOT NULL,
    value character varying(255),
    description text
);

CREATE SEQUENCE public.measurment_types_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.measurment_types (
    id integer DEFAULT nextval('public.measurment_types_seq'::regclass) NOT NULL,
    short_name character varying(50),
    description text
);

CREATE SEQUENCE public.military_ranks_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.military_ranks (
    id integer DEFAULT nextval('public.military_ranks_seq'::regclass) NOT NULL,
    description character varying(255)
);

INSERT INTO public.calc_header_correction (id, measurment_type_id, description, "values") VALUES
(1, 1, 'Заголовок для Таблицы № 2 (ДМК)', '{0,1,2,3,4,5,6,7,8,9,10,20,30,40,50}'),
(2, 2, 'Заголовок для Таблицы № 2 (ВР)', '{0,1,2,3,4,5,6,7,8,9,10,20,30,40,50}');

INSERT INTO public.calc_height_correction (id, height, measurment_type_id) VALUES
(1, 200, 1), (2, 400, 1), (3, 800, 1), (4, 1200, 1), (5, 1600, 1),
(6, 2000, 1), (7, 2400, 1), (8, 3000, 1), (9, 4000, 1), (10, 200, 2),
(11, 400, 2), (12, 800, 2), (13, 1200, 2), (14, 1600, 2), (15, 2000, 2),
(16, 2400, 2), (17, 3000, 2), (18, 4000, 2);

INSERT INTO public.calc_temperature_correction (temperature, correction) VALUES
(0.00, 0.50), (5.00, 0.50), (10.00, 1.00), (20.00, 1.00), (25.00, 2.00),
(30.00, 3.50), (40.00, 4.50);

INSERT INTO public.calc_temperature_height_correction (id, calc_height_id, calc_temperature_header_id, positive_values, negative_values) VALUES
(1, 1, 1, '{1,2,3,4,5,6,7,8,9,10,20,30,30,30}', '{-1,-2,-3,-4,-5,-6,-7,-8,-8,-9,-20,-29,-39,-49}'),
(2, 2, 1, '{1,2,3,4,5,6,7,8,9,10,20,30,30,30}', '{-1,-2,-3,-4,-5,-6,-6,-7,-8,-9,-19,-29,-38,-48}'),
(3, 3, 1, '{1,2,3,4,5,6,7,8,9,10,20,30,30,30}', '{-1,-2,-3,-4,-5,-6,-6,-7,-7,-8,-18,-28,-37,-46}');

INSERT INTO public.calc_temperatures_correction (temperature, correction) VALUES
(0.00, 0.50), (5.00, 0.50), (10.00, 1.00), (20.00, 1.00), (25.00, 2.00),
(30.00, 3.50), (40.00, 4.50);

INSERT INTO public.employees (id, name, birthday, military_rank_id) VALUES
(1, 'Воловиков Александр Сергеевич', '1978-06-24 00:00:00', 2),
(2, 'ЧУПНСМмгРзмПЦИЧЦЙЦРаЛШкОж', '1990-10-09 02:10:12.03467', 2),
(3, 'НжпЦеоЩоЪйЭйжзРЯЛлиМнЫдон', '1983-01-20 23:44:52.731136', 1);

INSERT INTO public.measurment_baths (id, emploee_id, measurment_input_param_id, started) VALUES
(1, 1, 1, '2025-02-28 00:39:49.931212'),
(2, 2, 2, '2025-02-04 20:05:03.149174'),
(3, 2, 3, '2025-02-04 02:54:57.642577');

-- Insert into measurment_input_params
INSERT INTO public.measurment_input_params (id, measurment_type_id, height, temperature, pressure, wind_direction, wind_speed, bullet_demolition_range) VALUES
(1, 1, 100.00, 12.00, 34.00, 0.20, 45.00, 0.00),
(2, 2, 400.00, 10.00, 687.00, 52.00, 13.00, 0.00),
(3, 1, 390.00, 49.00, 814.00, 5.00, 28.00, 0.00),
(4, 2, 406.00, 2.00, 586.00, 44.00, 8.00, 0.00),
(5, 1, 68.00, 32.00, 789.00, 29.00, 57.00, 0.00),
(6, 1, 359.00, 1.00, 611.00, 50.00, 8.00, 0.00),
(7, 1, 249.00, 29.00, 686.00, 47.00, 48.00, 0.00),
(8, 1, 162.00, 4.00, 519.00, 57.00, 31.00, 0.00),
(9, 1, 317.00, 44.00, 551.00, 23.00, 35.00, 0.00),
(10, 1, 56.00, 44.00, 571.00, 55.00, 23.00, 0.00),
(11, 1, 358.00, 41.00, 711.00, 35.00, 40.00, 0.00),
(12, 1, 396.00, 29.00, 711.00, 14.00, 16.00, 0.00),
(13, 1, 456.00, 1.00, 535.00, 21.00, 23.00, 0.00),
(14, 1, 447.00, 16.00, 511.00, 43.00, 16.00, 0.00),
(15, 2, 295.00, 8.00, 549.00, 37.00, 19.00, 0.00),
(16, 1, 226.00, 15.00, 570.00, 54.00, 32.00, 0.00),
(17, 1, 567.00, 24.00, 539.00, 29.00, 10.00, 0.00),
(18, 2, 599.00, 48.00, 659.00, 16.00, 23.00, 0.00),
(19, 2, 67.00, 38.00, 764.00, 19.00, 56.00, 0.00),
(20, 1, 140.00, 34.00, 815.00, 1.00, 4.00, 0.00),
(21, 2, 80.00, 44.00, 573.00, 16.00, 23.00, 0.00),
(22, 1, 230.00, 9.00, 680.00, 23.00, 4.00, 0.00),
(23, 1, 110.00, 7.00, 604.00, 6.00, 37.00, 0.00),
(24, 1, 119.00, 47.00, 706.00, 54.00, 38.00, 0.00),
(25, 1, 229.00, 20.00, 500.00, 45.00, 1.00, 0.00),
(26, 2, 456.00, 3.00, 643.00, 39.00, 43.00, 0.00),
(27, 2, 515.00, 36.00, 725.00, 0.00, 45.00, 0.00),
(28, 2, 422.00, 44.00, 795.00, 8.00, 38.00, 0.00),
(29, 2, 400.00, 46.00, 754.00, 6.00, 50.00, 0.00),
(30, 2, 384.00, 34.00, 831.00, 17.00, 55.00, 0.00),
(31, 1, 494.00, 10.00, 728.00, 16.00, 35.00, 0.00),
(32, 1, 121.00, 8.00, 538.00, 28.00, 30.00, 0.00),
(33, 2, 369.00, 27.00, 571.00, 33.00, 33.00, 0.00),
(34, 1, 88.00, 29.00, 554.00, 29.00, 14.00, 0.00),
(35, 2, 225.00, 13.00, 597.00, 40.00, 10.00, 0.00),
(36, 2, 467.00, 39.00, 657.00, 17.00, 51.00, 0.00),
(37, 1, 392.00, 44.00, 529.00, 36.00, 43.00, 0.00),
(38, 2, 295.00, 13.00, 778.00, 3.00, 22.00, 0.00),
(39, 1, 510.00, 43.00, 531.00, 33.00, 15.00, 0.00),
(40, 2, 498.00, 40.00, 746.00, 8.00, 11.00, 0.00),
(41, 2, 506.00, 46.00, 689.00, 55.00, 20.00, 0.00),
(42, 2, 180.00, 35.00, 756.00, 53.00, 38.00, 0.00),
(43, 1, 159.00, 35.00, 609.00, 42.00, 50.00, 0.00),
(44, 2, 219.00, 21.00, 637.00, 38.00, 20.00, 0.00),
(45, 1, 292.00, 22.00, 672.00, 39.00, 37.00, 0.00),
(46, 2, 313.00, 24.00, 826.00, 41.00, 27.00, 0.00),
(47, 1, 544.00, 23.00, 583.00, 36.00, 19.00, 0.00),
(48, 1, 486.00, 5.00, 544.00, 49.00, 16.00, 0.00),
(49, 2, 412.00, 44.00, 599.00, 14.00, 3.00, 0.00),
(50, 1, 70.00, 25.00, 516.00, 20.00, 26.00, 0.00);

-- Insert into measurment_settings
INSERT INTO public.measurment_settings (key, value, description) VALUES
('min_temperature', '-10', 'Минимальное значение температуры'),
('max_temperature', '50', 'Максимальное значение температуры'),
('min_pressure', '500', 'Минимальное значение давления'),
('max_pressure', '900', 'Максимальное значение давления'),
('min_wind_direction', '0', 'Минимальное значение направления ветра'),
('max_wind_direction', '59', 'Максимальное значение направления ветра'),
('calc_table_temperature', '15.9', 'Табличное значение температуры'),
('calc_table_pressure', '750', 'Табличное значение наземного давления'),
('min_height', '0', 'Минимальная высота'),
('max_height', '400', 'Максимальная высота');

-- Insert into measurment_types
INSERT INTO public.measurment_types (id, short_name, description) VALUES
(1, 'ДМК', 'Десантный метео комплекс'),
(2, 'ВР', 'Ветровое ружье');

-- Insert into military_ranks
INSERT INTO public.military_ranks (id, description) VALUES
(1, 'Рядовой'),
(2, 'Лейтенант');
