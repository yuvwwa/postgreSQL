do $$
declare
    var_i integer;
    var_j integer;
    employee_count integer default 5;
    param_count integer default 100;
    random_name text;
    random_birthday timestamp without time zone;
    random_military_rank_id integer;
    names text[] := ARRAY['Иванов Иван Иванович', 
                         'Федоров Федор Федорович', 
                         'Сергеев Сергей Сергеевич', 
                         'Сидоров Сидор Сидорович', 
                         'Петров Петр Петрович'];
begin
-- Сначала генерируем сотрудников, далее параметры
    for var_i in 1..employee_count loop
        random_name := names[var_i];
        random_birthday := '1970-01-01 00:00:00'::timestamp + 
                          (random() * (interval '30 years'));
        random_military_rank_id := floor(random()* 2 + 1);
        
        insert into yulya.employees(id, name, birthday, military_rank_id) 
		values (nextval('yulya.employees_seq'), random_name, random_birthday, random_military_rank_id);

        for var_j in 1..param_count loop
            insert into yulya.measurment_input_params (id, measurment_type_id, height, temperature, pressure, wind_direction, wind_speed) 
			values (
                nextval('yulya.measurment_input_params_seq'),
                floor(random()*5 + 1), -- Типы званий от 1 до 5
                random()*9999, -- Высота от 0 до 9999
                random()*116 - 58, -- Температура от -58 до 58 по ТЗ
                random() * 400 + 500, -- Давление от 500 до 900 по ТЗ
                floor(random() * 60),  -- Направление ветра от 0 до 59 по ТЗ
                random() * 50  -- Скорость ветра от 0 до 50
            );
        end loop;
    end loop;
end $$;

select * from yulya.employees limit 10;
select * from yulya.measurment_input_params limit 10;