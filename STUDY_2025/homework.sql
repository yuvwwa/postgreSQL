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

drop table if exists public.calc_wind_correction;
drop sequence if exists public.calc_wind_correction_seq;

create sequence public.calc_wind_correction_seq
	start with 1
	increment by 1
	no minvalue
	no maxvalue
	cache 1;

create table public.calc_wind_correction(
	id integer default nextval('public.calc_wind_correction_seq'::regclass) not null,
	height integer not null,
	wind_drift_distance integer[] not null,
	wind_speed integer[],
	wind_correction numeric(8,2)
);

insert into public.calc_wind_correction(height, wind_drift_distance, wind_speed, wind_correction)
VALUES 
    (200, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[3,4,5,6,7,7,8,9,10,11,12,12],
	0.00),
	(400, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[4,5,6,7,8,9,10,11,12,13,14,15],
	1.00),
	(800, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[4,5,6,7,8,9,10,11,13,14,15,16],
	2.00),
	(1200, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[4,5,7,8,8,9,11,12,13,15,15,16],
	2.00),
	(1600, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[4,6,7,8,9,10,11,13,14,15,17,17],
	3.00),
	(2000, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[4,6,7,8,9,10,11,13,14,16,17,18],
	3.00),
	(2400, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[4,6,8,9,9,10,12,14,15,16,18,19],
	3.00),
	(3000, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[5,6,8,9,10,11,12,14,15,17,18,19],
	4.00),
	(4000, 
	array[40,50,60,70,80,90,100,110,120,130,140,150],
	array[5,6,8,9,10,11,12,14,16,18,19,20],
	4.00);

select * from public.calc_wind_correction;

DO $$
BEGIN
    RAISE NOTICE 'json %', 
    (SELECT json_agg(row_to_json(calc_wind_correction))
     FROM public.calc_wind_correction);
END $$;

-- процедура

drop procedure sp_calculate_wind_gun_corrections(input_params,jsonb);
create or replace procedure public.sp_calculate_wind_gun_corrections(
    in par_input public.input_params,
    inout par_results jsonb
)
language 'plpgsql'
as $body$
declare
    var_wind_correction_record record;  -- запись для хранения данных из таблицы
    var_wind_speed integer[];  -- скорость ветра
    var_wind_correction numeric(8,2);  -- поправка ветра
begin
    -- поиск данных в таблице calc_wind_correction по высоте и дальности сноса пуль
    select wind_speed, wind_correction
    into var_wind_speed, var_wind_correction
    from public.calc_wind_correction
    where height = par_input.height
      and par_input.bullet_demolition_range = any(wind_drift_distance)
    limit 1;

    -- если данные не найдены значение 0
    if not found then
        var_wind_speed := 0;
        var_wind_correction := 0;
    end if;

    par_results := jsonb_build_object(
        'height', par_input.height,
        'temperature', par_input.temperature,
        'pressure', par_input.pressure,
        'wind_direction', par_input.wind_direction,
        'wind_speed', var_wind_speed,
        'wind_correction', var_wind_correction
    );

    raise notice 'результаты расчета: %', par_results;
end;
$body$;

do $$
declare
    input_data public.input_params;
    results jsonb;
begin
    input_data.height := 2000.0;
    input_data.temperature := 23.5;
    input_data.pressure := 750.0;
    input_data.wind_direction := 180.0;
    input_data.wind_speed := 5.0;
    input_data.bullet_demolition_range := 100.0;

    call public.sp_calculate_wind_gun_corrections(
        input_data,
        results
    );

    raise notice 'результаты расчета: %', results;
end $$;

-- индексы

drop index if exists ix_measurment_baths_emploee_id;
drop index if exists ix_calc_header_correction_measurment_type_id;
drop index if exists ix_calc_height_correction_measurment_type_id;
drop index if exists ix_calc_temperature_height_correction_calc_height_id;
drop index if exists ix_calc_temperature_height_correction_calc_temperature_header_id;
drop index if exists ix_measurment_input_params_measurment_type_id;
drop index if exists ix_measurment_input_params_bullet_demolition_range;
drop index if exists ix_employees_military_rank_id;
drop index if exists ix_measurment_baths_measurment_input_param_id;
drop index if exists ix_measurment_settings_key;
drop index if exists ix_measurment_types_short_name;
drop index if exists ix_military_ranks_description;


create index if not exists ix_measurment_baths_emploee_id
    on public.measurment_baths (emploee_id);

create index if not exists ix_calc_header_correction_measurment_type_id
    on public.calc_header_correction (measurment_type_id);

create index if not exists ix_calc_height_correction_measurment_type_id
    on public.calc_height_correction (measurment_type_id);

create index if not exists ix_calc_temperature_height_correction_calc_height_id
    on public.calc_temperature_height_correction (calc_height_id);

create index if not exists ix_calc_temperature_height_correction_calc_temperature_header_id
    on public.calc_temperature_height_correction (calc_temperature_header_id);

create index if not exists ix_measurment_input_params_measurment_type_id
    on public.measurment_input_params (measurment_type_id);

create index if not exists ix_measurment_input_params_bullet_demolition_range
    on public.measurment_input_params (bullet_demolition_range);

create index if not exists ix_employees_military_rank_id
    on public.employees (military_rank_id);

create index if not exists ix_measurment_baths_measurment_input_param_id
    on public.measurment_baths (measurment_input_param_id);

create index if not exists ix_measurment_settings_key
    on public.measurment_settings (key);

create index if not exists ix_measurment_types_short_name
    on public.measurment_types (short_name);

create index if not exists ix_military_ranks_description
    on public.military_ranks (description);

drop view if exists public.measument_fails_report;

-- Запрос с прошлого задания  оформить в виде представления (View и CTE)
-- ФИО  | Должность | Кол-во измерений | Количество ошибочных данных |
create view public.measument_fails_report as
with 
measurement_quantity as (
    select emploee_id, count(*) as measurement_quantity
    from public.measurment_input_params as t1
    inner join public.measurment_baths as t2 on t2.measurment_input_param_id = t1.id
    group by emploee_id
),
fails as (
    select
        emploee_id,
        count(*) as fails
    from public.measurment_input_params as t1
    inner join public.measurment_baths as t2 on t2.measurment_input_param_id = t1.id
    where 
        (public.fn_check_input_params(height, temperature, pressure, wind_direction, wind_speed, bullet_demolition_range)::public.check_result).is_check = false
    group by emploee_id
)
select
    t1.name as username, 
    t2.description as position, 
    coalesce(tt1.measurement_quantity, 0) as measurement_quantity, 
    coalesce(tt2.fails, 0) as fails
from public.employees as t1
inner join public.military_ranks as t2 on t1.military_rank_id = t2.id
left join measurement_quantity as tt1 on tt1.emploee_id = t1.id
left join fails as tt2 on tt2.emploee_id = t1.id
order by fails desc;

select * from public.measument_fails_report;

drop view if exists public.effective_measurement_height_report;
create view public.effective_measurement_height_report as
with 
measurement_stats as (
    select 
        emploee_id, 
        min(height) as min_height,
        max(height) as max_height,
        count(*) as measurements,
        sum(
            case 
                when (public.fn_check_input_params(height, temperature, pressure, 
                                                  wind_direction, wind_speed, 
                                                  bullet_demolition_range)::public.check_result).is_check = false 
                then 1 
                else 0 
            end
        ) as fails
    from public.measurment_input_params as t1
    inner join public.measurment_baths as t2 on t2.measurment_input_param_id = t1.id
    group by emploee_id
)
select
    t1.name as username, -- ФИО пользователя
    t2.description as position, -- Звание
    tt.min_height, -- Мин. высота метеопоста
    tt.max_height, -- Макс. высота метепоста
    tt.measurements, -- Всего измерений
    tt.fails -- Из них ошибочны
from measurement_stats as tt
inner join public.employees as t1 on tt.emploee_id = t1.id
inner join public.military_ranks as t2 on t1.military_rank_id = t2.id
-- Необходмо вывести список пользователей у которых меньше 10 ошибок в наборе данных, которые делали не менее 5- ти измерения
-- Таких не существует, поэтому закомментировано
-- where tt.fails < 10 and tt.measurements >= 5
order by tt.fails asc;


select * from public.effective_measurement_height_report;

-- Добавим таблицы, типы из кода преподавателя
/*
 3. Подготовка расчетных структур
 ==========================================
 */
drop type  if exists interpolation_type cascade;
drop type if exists input_params cascade;
drop type if exists check_result cascade;
drop type if exists temperature_correction cascade;
drop type if exists wind_direction_correction cascade;
drop table if exists calc_temperature_correction;
drop table if exists calc_header_correction;
drop table if exists calc_temperature_height_correction;
drop table if exists calc_height_correction;
drop table if exists calc_wind_speed_height_correction;
drop sequence if exists calc_wind_speed_height_correction_seq;
drop sequence if exists calc_temperature_height_correction_seq;
drop sequence if exists calc_height_correction_seq;
drop sequence if exists calc_header_correction_seq;
drop index if exists ix_calc_header_correction_header_type;
drop procedure if exists public.sp_calc_wind_speed_deviation;

create table calc_temperature_correction
(
   temperature numeric(8,2) not null primary key,
   correction numeric(8,2) not null
);

insert into public.calc_temperature_correction(temperature, correction)
Values(0, 0.5),(5, 0.5),(10, 1), (20,1), (25, 2), (30, 3.5), (40, 4.5);

create type interpolation_type as
(
	x0 numeric(8,2),
	x1 numeric(8,2),
	y0 numeric(8,2),
	y1 numeric(8,2)
);

-- Тип для входных параметров
create type input_params as
(
	height numeric(8,2),
	temperature numeric(8,2),
	pressure numeric(8,2),
	wind_direction numeric(8,2),
	wind_speed numeric(8,2),
	bullet_demolition_range numeric(8,2)
);

-- Тип с результатами проверки
create type check_result as
(
	is_check boolean,
	error_message text,
	params input_params
);

-- Результат расчета коррекций для температуры по высоте
create type temperature_correction as
(
	calc_height_id integer,
	height integer,
	-- Приращение по температуре
	temperature_deviation integer
);

-- Результат расчета скорости среднего ветра и приращение среднего ветра
create type wind_direction_correction as
(
	calc_height_id integer,
	height integer,
	-- Приращение по скорости ветра
	wind_speed_deviation integer,
	-- Приращение среднего ветра
	wind_deviation integer
);


-- Таблица заголовков к поправочных таблицам
create sequence calc_header_correction_seq;
create table calc_header_correction
(
	id integer not null primary key default nextval('public.calc_header_correction_seq'),
	measurment_type_id integer not null,
	header varchar(100) not null,
	description text not null,
	values integer[] not null
);

-- Добавим уникальный индекс для отсечки ошибок
create unique index ix_calc_header_correction_header_type on calc_header_correction(measurment_type_id, header);

-- Добавим заголовки
insert into calc_header_correction(measurment_type_id, header, description, values) 
values (1, 'table2', 'Заголовок для Таблицы № 2 (ДМК)', array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50]),
       (2, 'table2','Заголовок для Таблицы № 2 (ВР)', array[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50]),
	   (2, 'table3', 'Заголовок для Таблицы № 3 (ВР)', array[40,50,60,70,80,90,100,110,120,130,140,150]);


-- Таблица 2 список высот в разрезе типа оборудования
create sequence calc_height_correction_seq;
create table calc_height_correction
(
	id integer primary key not null default nextval('public.calc_height_correction_seq'),
	height integer not null,
	measurment_type_id integer not null
);

insert into calc_height_correction(height, measurment_type_id)
values(200,1),(400,1),(800,1),(1200,1),(1600,1),(2000,1),(2400,1),(3000,1),(4000,1),
	  (200,2),(400,2),(800,2),(1200,2),(1600,2),(2000,2),(2400,2),(3000,2),(4000,2);


-- Таблица 2 набор корректировок
create sequence calc_temperature_height_correction_seq;
create table calc_temperature_height_correction
(
	id integer primary key not null default nextval('public.calc_temperature_height_correction_seq'),
	calc_height_id integer not null,
	calc_temperature_header_id integer not null,
	positive_values numeric[],
	negative_values numeric[]
);

-- Данные для ветрового ружья
insert into calc_temperature_height_correction(calc_height_id, calc_temperature_header_id, positive_values, negative_values)
values
(10,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[ -1, -2, -3, -4, -5, -6, -7, -8, -8, -9, -20, -29, -39, -49]), --200
(11,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -4, -5, -6, -6, -7, -8, -9, -19, -29, -38, -48]), --400
(12,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -4, -5, -6, -6, -7, -7, -8, -18, -28, -37, -46]), --800
(13,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -4, -4, -5, -5, -6, -7, -8, -17, -26, -35, -44]), --1200
(14,1,array[ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -3, -4, -4, -5, -6, -7, -7, -17, -25, -34, -42]), --1600
(15,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -3, -4, -4, -5, -6, -6, -7, -16, -24, -32, -40]), --2000
(16,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -2, -3, -4, -4, -5, -5, -6, -7, -15, -23, -31, -38]), --2400
(17,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -2, -3, -4, -4, -4, -5, -5, -6, -15, -22, -30, -37]), --3000
(18,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[ -1, -2, -2, -3, -4, -4, -4, -4, -5, -6, -14, -20, -27, -34]); --4000



-- Данные для ДМК
insert into calc_temperature_height_correction(calc_height_id, calc_temperature_header_id, positive_values, negative_values)
values
(1,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[ -1, -2, -3, -4, -5, -6, -7, -8, -8, -9, -20, -29, -39, -49]), --200
(2,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -4, -5, -6, -6, -7, -8, -9, -19, -29, -38, -48]), --400
(3,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -4, -5, -6, -6, -7, -7, -8, -18, -28, -37, -46]), --800
(4,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -4, -4, -5, -5, -6, -7, -8, -17, -26, -35, -44]), --1200
(5,1,array[ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -3, -4, -4, -5, -6, -7, -7, -17, -25, -34, -42]), --1600
(6,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -3, -3, -4, -4, -5, -6, -6, -7, -16, -24, -32, -40]), --2000
(7,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -2, -3, -4, -4, -5, -5, -6, -7, -15, -23, -31, -38]), --2400
(8,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[-1, -2, -2, -3, -4, -4, -4, -5, -5, -6, -15, -22, -30, -37]), --3000
(9,1,array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 30, 30], array[ -1, -2, -2, -3, -4, -4, -4, -4, -5, -6, -14, -20, -27, -34]); --4000


-- Таблица 3 корректировка сноса пуль
-- Для расчета приращение среднего ветра относительно направления приземного ветра
create sequence calc_wind_speed_height_correction_seq;
create table calc_wind_speed_height_correction
(
	id integer not null primary key default nextval('public.calc_wind_speed_height_correction_seq'),
	calc_height_id integer not null,
	values integer[] not null,
	delta integer not null
);

-- Для ветрового ружья
insert into calc_wind_speed_height_correction(calc_height_id, values, delta)
values
(10, array[3, 4, 5, 6, 7, 7, 8, 9, 10, 11, 12, 12], 0),	-- 200
(11, array[4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], 1),-- 400
(12, array[4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16], 2), -- 800
(13, array[4, 5, 7, 8, 8, 9, 11, 12, 13, 15, 15, 16], 2), -- 1200
(14, array[4, 6, 7, 8, 9, 10, 11, 13, 14, 15, 17, 17], 3), -- 1600
(15, array[4, 6, 7, 8, 9, 10, 11, 13, 14, 16, 17, 18], 3), -- 2000
(16, array[4, 6, 8, 9, 9, 10, 12, 14, 15, 16, 18, 19], 3), -- 2400
(17, array[5, 6, 8, 9, 10, 11, 12, 14, 15, 17, 18, 19], 4), -- 3000
(18, array[5, 6, 8, 9, 10, 11, 12, 14, 16, 18, 19, 20],4) -- 4000
;


-- Процедура для расчета скорости среднего ветра и направления среднего ветра
create or replace procedure public.sp_calc_wind_speed_deviation(
	IN par_bullet_demolition_range numeric,
	IN par_measurement_type_id integer,
	INOUT par_corrections wind_direction_correction[])
language 'plpgsql'
as $body$
declare
	var_row record;
	var_index integer;
	var_correction wind_direction_correction;
	var_header_correction integer[];
	var_header_index integer;
	var_table integer[];
	var_deviation integer;
	var_table_row text;
begin

	if coalesce(par_bullet_demolition_range, -1) < 0 then
		raise exception 'Некорректно переданы параметры! Значение par_bullet_demolition_range %', par_bullet_demolition_range; 
	end if;
	
	if not exists ( select 1 from public.calc_height_correction 
			where measurment_type_id = par_measurement_type_id) then

		raise exception 'Для устройства с кодом % не найдены значения высот в таблице calc_height_correction!', par_measurement_type_id;
	end if;	

	-- Получаем индекс корректировки
	var_index := (par_bullet_demolition_range / 10)::integer - 4;
	if var_index < 0 then
		var_index := 1;
	end if;	


	-- Получаем заголовок 
	var_header_correction := (select values from public.calc_header_correction
				where 
					header = 'table3'
					and measurment_type_id  = par_measurement_type_id );

	-- Проверяем данные
	if array_length(var_header_correction, 1) = 0 then
		raise exception 'Невозможно произвести расчет по высоте. Некорректные исходные данные или настройки';
	end if;

	if array_length(var_header_correction, 1) < var_index then
		raise exception 'Невозможно произвести расчет по высоте. Некорректные исходные данные или настройки';
	end if;			

	raise notice '| Высота   | Поправка  |';
	raise notice '|----------|-----------|';
	
	for var_row in
		select t1.height, t2.* from calc_height_correction as t1
		inner join public.calc_wind_speed_height_correction as t2
		on t2.calc_height_id = t1.id
		where  
			t1.measurment_type_id = par_measurement_type_id loop

		-- Получаем индекс
		var_header_index := abs(var_index % 10);
		var_table := var_row.values;

		-- Поправка на скорость среднего ветра
		var_deviation:= var_table[ var_header_index  ];

		select '|' || lpad(var_row.height::text, 10, ' ') || '|' || lpad(var_deviation::text, 11,' ') || '|'
		into
			var_table_row;
				
		raise notice '%', var_table_row;

		var_correction.calc_height_id := var_row.calc_height_id;
		var_correction.height := var_row.height;

		-- Скорость среднего ветра
		var_correction.wind_speed_deviation := var_deviation;

		-- Приращение среднего ветра относительно направления приземного ветра
		var_correction.wind_deviation = var_row.delta;
		
		par_corrections := array_append(par_corrections, var_correction);
	end loop;	

	raise notice '|----------|-----------|';

end;
$body$;