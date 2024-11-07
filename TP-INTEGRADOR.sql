--PUNTO 1: NUEVO EVENTO EN EL CALENDARIO
CREATE OR REPLACE FUNCTION fn_tr_event_ins_upd() RETURNS trigger AS
$BODY$
BEGIN
IF NEW.school_date>=CURRENT_DATE 
THEN
RETURN NEW;
ELSE
RAISE EXCEPTION 'El evento tiene una fecha anterior al dia de hoy';
END IF;
END;
$BODY$ LANGUAGE plpgsql;

CREATE TRIGGER trg_event_ins_upd BEFORE INSERT OR UPDATE ON calendar_events
FOR EACH ROW EXECUTE PROCEDURE fn_tr_event_ins_upd();

--PRUEBA 
select * from calendar_events ce 



--PUNTO 2: FECHA DE ENTREGA DE NOTAS
CREATE OR REPLACE FUNCTION fn_tr_gradeposting_ins_upd() RETURNS trigger AS
$BODY$
BEGIN
IF NEW.mp='QTR' and NEW.post_start_date>NEW.end_date
THEN
RETURN NEW;
ELSE
RAISE EXCEPTION 'La fecha de Grade Posting debe ser posterior a la finalización del cuarto';
END IF;
END;
$BODY$ LANGUAGE plpgsql;


CREATE TRIGGER trg_gradeposting_ins_upd BEFORE INSERT OR UPDATE ON school_marking_periods
FOR EACH ROW EXECUTE PROCEDURE fn_tr_gradeposting_ins_upd();

--PRUEBA
select * from school_marking_periods smp 

--PUNTO 3:ALTA DE ESTUDIANTE [FECHA DE NACIMIENTO]
CREATE OR REPLACE FUNCTION fn_trg_student_ins_upd() RETURNS trigger AS
$BODY$
BEGIN
IF NEW.custom_200000004 IS NOT NULL
THEN
RETURN NEW;
ELSE
RAISE EXCEPTION 'Debe ingresar la fecha de nacimiento';
END IF;
END;
$BODY$ LANGUAGE plpgsql;

CREATE TRIGGER trg_student_ins_upd BEFORE INSERT OR UPDATE ON students
FOR EACH ROW EXECUTE PROCEDURE fn_trg_student_ins_upd();

--PRUEBA
select * from students


--PUNTO 4: ALTA DE ESTUDIANTE [NUMERO DE IDENTIFICACION]
create DOMAIN tipoCUIL AS VARCHAR not NULL
CHECK(
VALUE ~ '^20\d{8}\d+$' or
VALUE ~ '^23\d{8}\d+$' or
VALUE ~ '^27\d{8}\d+$' or
VALUE ~ '^24\d{8}\d+$');

alter table students alter column custom_200000003 type tipoCUIL; --Modificamos el tipo de la tabla


--PUNTO 5: DIRECCION PARA ASCENDER Y DESCENDER DEL AUTOBUS

--CREAR VISTA
create view bus_address as (select s.student_id,
sum(case when bus_pickup is not null then 1 else 0 end) as pickup,
sum(case when bus_dropoff is not null then 1 else 0 end) as dropoff
from students s full outer join students_join_address sja
on (sja.student_id=s.student_id)
group by s.student_id);


--PRUEBA 
select * from bus_address



--PARA PICK UP
CREATE OR REPLACE FUNCTION fn_trg_pickup_ins_upd() RETURNS trigger AS
$BODY$
BEGIN
IF (NEW.bus_pickup IS NOT NULL and (select pickup from bus_address where new.student_id= bus_address.student_id ) = 0 ) or  new.bus_pickup is null 
or (new.bus_pickup = old.bus_pickup) --si es nula o se cambio sobre la misma entidad.
THEN
RETURN NEW;
ELSE
RAISE EXCEPTION 'El alumno ya posee un Bus Pickup';
END IF;
END;
$BODY$ LANGUAGE plpgsql;


CREATE TRIGGER trg_busPickUp_ins_upd BEFORE INSERT OR UPDATE ON students_join_address
FOR EACH ROW EXECUTE PROCEDURE fn_trg_pickup_ins_upd();


--DROPOFF
CREATE OR REPLACE FUNCTION fn_trg_dropoff_ins_upd() RETURNS trigger AS
$BODY$
BEGIN
IF (NEW.bus_dropoff IS NOT NULL and (select dropoff from bus_address where new.student_id=bus_address.student_id ) = 0 ) or new.bus_dropoff is null
or (new.bus_dropoff = old.bus_dropoff) --si es nula o se cambio sobre la misma entidad.
THEN
RETURN NEW;
ELSE
RAISE EXCEPTION 'El alumno ya posee un Bus Drop Off';
END IF;
END;
$BODY$ LANGUAGE plpgsql;


CREATE TRIGGER trg_busDropOff_ins_upd BEFORE INSERT OR UPDATE ON students_join_address
FOR EACH ROW EXECUTE PROCEDURE fn_trg_dropoff_ins_upd();




--PUNTO 6: CARACTERISTICAS DE DOMINIO
--Crear dominio
create DOMAIN tipoKOSHER AS VARCHAR
CHECK(
VALUE ~ 'CARNE' or
VALUE ~ 'LACTEOS' or
VALUE ~ 'PAREVE' or
VALUE ~ 'PASCUA KOSHER');

--Agregamos atributos a la tabla
alter table food_service_items add column vegetariano boolean;
alter table food_service_items add column kosher boolean;
alter table food_service_items add column tipo_kosher tipoKOSHER;

--Actualizamos valores de tuplas ya cargadas
update food_service_items set vegetariano = false where vegetariano is null;
update food_service_items set kosher = false where kosher is null;

--PRUEBA
select * from food_service_items fsi


--PUNTO 7: LOG DE MODIFICACION DE PRECIOS

--Creamos tabla log
create table log_mod_prices (
id_log SERIAL primary key,
item_id int4,
fecha timestamp,
bef_price numeric(9,2) ,
aft_price numeric(9,2));

--Funcion y trigger
CREATE OR REPLACE FUNCTION fn_trg_logPrices_ins_upd() RETURNS trigger AS
$BODY$
BEGIN
IF NEW.price <> OLD.price
THEN
insert into log_mod_prices (item_id,fecha,bef_price,aft_price) values (new.item_id,current_date,old.price,new.price);
END IF;
return new;
END;
$BODY$ LANGUAGE plpgsql;

CREATE TRIGGER trg_logPrices_ins_upd AFTER update of price on food_service_items
FOR EACH ROW EXECUTE PROCEDURE fn_trg_logPrices_ins_upd();

--PRUEBA
select * from food_service_items fsi;

update food_service_items set price = 0.25 where item_id = 3

select * from log_mod_prices


--INFORMES

/*Un reporte se generará el último día de cada mes, donde consten todas las referencias (referrals) disciplinarias del último mes;*/
select dr.entry_date as DATE_REFERRAL , category_1 as INFRACCION, category_2 as CASTIGO, category_5 as SUSPENSION,dr.created_at as FECHA_CREACION
from discipline_referrals dr
join staff s on (dr.staff_id = s.staff_id)
where s.profile = 'teacher' and --PARA no ENERO
((extract (month from dr.entry_date)<>1 and
extract (month from dr.entry_date) = (extract(month from current_date) - 1) -- mes igual
and extract (year from dr.entry_date) = extract(year from current_date))
or --PARA ENERO
(extract (month from current_date)=1 and extract (year from dr.entry_date) =
(extract(year from current_date) - 1) and extract(month from dr.entry_date) = 12))


/*Un informe diario con intentos reiterados de acceso inválidos de cualquier usuario. Los casos que se deben incluir en el registro deben ser: 
 * aquellos usuarios que accedieron incorrectamente más de 10 veces en una hora determinada (por ejemplo, si el usuario “admin” tuvo más de 10 
 * intentos de acceso desde las 23:00 hasta las 23:59, se debe mostrar).*/

select * from ( select username,date(al.login_time) as date ,extract (hour from al.login_time) as hour , count(created_at) as cant_intentos from access_log al
where date(login_time) = date(current_date) and al.status is null
group by username , extract (hour from al.login_time),date(al.login_time)
) l where cant_intentos >10

/*Informe de aquellas transacciones de comidas realizadas por alumnos, donde el balance registrado en la cabecera no concuerde con el 
 * total registrado en el detalle de la transacción.*/

select fst.transaction_id as numero_transaccion,concat(s.first_name,' ',s.last_name) as nombre,
sum(fsti.amount) as balance_detalle,balance as balance_cabecera,abs(sum(fsti.amount) - balance) as diferencia
from food_service_transactions fst
inner join food_service_transaction_items fsti on (fst.transaction_id=fsti.transaction_id)
inner join students s on (s.student_id=fst.student_id)
group by fst.transaction_id,s.student_id
having sum(fsti.amount)<>balance



/*Informe de aquellos alumnos que en el año actual su balance sea negativo (la suma de su matrícula -fees- es mayor a la suma de sus pagos).*/

select s.student_id as id, concat(s.first_name,' ',s.last_name) as nombre,
sum(bf.amount) as total_matricula, sum(bp.amount) as total_pagos,
(sum(bf.amount)-sum(bp.amount)) as diferencia
from students s full outer join billing_fees bf on (s.student_id=bf.student_id)
full outer join billing_payments bp on (s.student_id=bp.student_id)
where date_part('year',current_date)=bp.syear and
date_part('year',current_date)=bf.syear
group by s.student_id
having sum(bp.amount)<sum(bf.amount)

















