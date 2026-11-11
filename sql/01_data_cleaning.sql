-- =====================================================================
-- moncity data warehouse
-- 01. data exploration and cleaning
--
-- the moncity schema is read only, so every cleaned table is created
-- in the local account and the warehouse is built from these tables.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. exploring the operational tables
-- ---------------------------------------------------------------------
select * from moncity.faculty;
select * from moncity.researchcenter;
select * from moncity.passenger;
select * from moncity.error;
select * from moncity.maintenancetype;
select * from moncity.booking;
select * from moncity.car;
select * from moncity.maintenance;
select * from moncity.accidentinfo;
select * from moncity.caraccident;
select * from moncity.maintenanceteam;
select * from moncity.belongto;

desc moncity.passenger;
desc moncity.booking;
desc moncity.car;
desc moncity.maintenance;
desc moncity.accidentinfo;
desc moncity.caraccident;


-- ---------------------------------------------------------------------
-- 2. null checks
-- ---------------------------------------------------------------------
select * from moncity.passenger
where passengerid is null or passengername is null or passengerrole is null
   or passengergender is null or passengerage is null or facultyid is null;

select * from moncity.booking
where bookingid is null or registrationno is null or bookingdate is null
   or departurezone is null or destinationzone is null or passengerid is null;

select * from moncity.maintenance
where maintenanceid is null or registrationno is null or maintenancedate is null
   or maintenancetype is null or maintenancecost is null or teamid is null;

select * from moncity.car
where registrationno is null or carmodel is null or manufacturingyear is null
   or carbodytype is null or numseats is null;

-- one accident in zonec has no accident id
select * from moncity.accidentinfo
where accidentid is null or accidentzone is null
   or car_damage_severity is null or errorcode is null;

select * from moncity.caraccident
where registrationno is null or accidentid is null;


-- ---------------------------------------------------------------------
-- 3. duplicate checks
-- ---------------------------------------------------------------------
select facultyid, count(*) from moncity.faculty group by facultyid having count(*) > 1;
select centerid, count(*) from moncity.researchcenter group by centerid having count(*) > 1;
select passengerid, count(*) from moncity.passenger group by passengerid having count(*) > 1;
select errorcode, count(*) from moncity.error group by errorcode having count(*) > 1;
select maintenancetype, count(*) from moncity.maintenancetype group by maintenancetype having count(*) > 1;
select registrationno, count(*) from moncity.car group by registrationno having count(*) > 1;
select maintenanceid, count(*) from moncity.maintenance group by maintenanceid having count(*) > 1;
select accidentid, count(*) from moncity.accidentinfo group by accidentid having count(*) > 1;
select accidentid, registrationno, count(*) from moncity.caraccident group by accidentid, registrationno having count(*) > 1;
select teamid, count(*) from moncity.maintenanceteam group by teamid having count(*) > 1;
select teamid, centerid, count(*) from moncity.belongto group by teamid, centerid having count(*) > 1;

-- booking t1218 appears twice with identical values
select bookingid, count(*) from moncity.booking group by bookingid having count(*) > 1;
select * from moncity.booking where bookingid = 'T1218';


-- ---------------------------------------------------------------------
-- 4. unrealistic and invalid values
-- ---------------------------------------------------------------------
-- ages outside the 18+ age groups
select * from moncity.passenger where passengerage < 18 or passengerage > 100;

-- maintenance m2000 has a cost of -200
select * from moncity.maintenance where maintenancecost <= 0;

-- zones outside zonea to zoned
select * from moncity.booking
where departurezone not in ('ZoneA','ZoneB','ZoneC','ZoneD')
   or destinationzone not in ('ZoneA','ZoneB','ZoneC','ZoneD');
select * from moncity.accidentinfo where accidentzone not in ('ZoneA','ZoneB','ZoneC','ZoneD');

-- inconsistent spelling or case in category values
select distinct carbodytype from moncity.car;
select distinct car_damage_severity from moncity.accidentinfo;


-- ---------------------------------------------------------------------
-- 5. foreign key checks
-- ---------------------------------------------------------------------
select * from moncity.booking where registrationno not in (select registrationno from moncity.car);
select * from moncity.booking where passengerid not in (select passengerid from moncity.passenger);
select * from moncity.maintenance where teamid not in (select teamid from moncity.maintenanceteam);
select * from moncity.caraccident where registrationno not in (select registrationno from moncity.car);

-- accident a2000 uses error010, which does not exist in the error table
select * from moncity.accidentinfo where errorcode not in (select errorcode from moncity.error);

-- passenger u163 has the faculty id 'Alienware', which is not a real faculty
select * from moncity.passenger where facultyid not in (select facultyid from moncity.faculty);


-- =====================================================================
-- 6. cleaned tables
-- =====================================================================
drop table booking_clean       cascade constraints purge;
drop table maintenance_clean   cascade constraints purge;
drop table accidentinfo_clean  cascade constraints purge;
drop table caraccident_clean   cascade constraints purge;
drop table passenger_clean     cascade constraints purge;

-- booking: both t1218 rows are identical, so distinct removes the copy
create table booking_clean as
select distinct * from moncity.booking;

-- maintenance: m2000 has a negative cost, so it is left out
create table maintenance_clean as
select * from moncity.maintenance
where maintenancecost > 0;

-- accidentinfo: a2000 (error code does not exist) and the accident with
-- no id are left out
create table accidentinfo_clean as
select * from moncity.accidentinfo
where errorcode in (select errorcode from moncity.error)
  and accidentid is not null;

-- caraccident: only keep accidents that are still in accidentinfo_clean
create table caraccident_clean as
select * from moncity.caraccident
where accidentid in (select accidentid from accidentinfo_clean);

-- passenger: u163 is kept, but the invalid faculty is set to null
create table passenger_clean as
select passengerid, passengername, passengerrole, passengergender, passengerage,
       case when facultyid in (select facultyid from moncity.faculty)
            then facultyid end as facultyid
from moncity.passenger;


-- ---------------------------------------------------------------------
-- 7. checks on the cleaned tables (all should return no rows)
-- ---------------------------------------------------------------------
select bookingid, count(*) from booking_clean group by bookingid having count(*) > 1;
select * from maintenance_clean where maintenancecost <= 0;
select * from accidentinfo_clean where errorcode not in (select errorcode from moncity.error);
select * from accidentinfo_clean
where accidentid is null or accidentzone is null
   or car_damage_severity is null or errorcode is null;
select * from passenger_clean where facultyid not in (select facultyid from moncity.faculty);
select * from caraccident_clean where accidentid not in (select accidentid from accidentinfo_clean);
