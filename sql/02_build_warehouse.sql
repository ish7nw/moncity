-- =====================================================================
-- moncity data warehouse
-- 02. version 1 star schema (snowflake with bridge tables)
--
-- oracle sql. run 01_data_cleaning.sql first, since every dimension
-- and fact table is built from the cleaned tables.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. drop old versions ("table does not exist" errors are expected on the first run)
-- ---------------------------------------------------------------------
drop table booking_fact        cascade constraints purge;
drop table maintenance_fact    cascade constraints purge;
drop table accident_fact       cascade constraints purge;
drop table car_accident_bridge cascade constraints purge;
drop table team_center_bridge  cascade constraints purge;
drop table team_dim            cascade constraints purge;
drop table accident_dim        cascade constraints purge;
drop table time_dim            cascade constraints purge;
drop table car_dim             cascade constraints purge;
drop table faculty_dim         cascade constraints purge;
drop table age_group_dim       cascade constraints purge;
drop table maint_type_dim      cascade constraints purge;
drop table center_dim          cascade constraints purge;
drop table accident_zone_dim   cascade constraints purge;
drop table error_code_dim      cascade constraints purge;
drop table severity_dim        cascade constraints purge;


-- =====================================================================
-- 1. dimensions
-- =====================================================================

-- time_dim: one row per month that has a booking or maintenance record
create table time_dim as
select distinct
       to_char(d, 'yyyymm')                as timeid,
       to_number(to_char(d, 'mm'))         as month,
       to_number(to_char(d, 'yyyy'))       as year
from (
      select bookingdate     as d from booking_clean
      union
      select maintenancedate as d from maintenance_clean
     );

-- car_dim
create table car_dim as
select distinct
       registrationno,
       carbodytype,
       numseats
from moncity.car;

-- faculty_dim
create table faculty_dim as
select distinct
       facultyid,
       facultyname
from moncity.faculty;

-- age_group_dim: fixed bands (type 0, never changes)
create table age_group_dim (
    agegroupid    number(1),
    agegroupdesc  varchar2(40)
);
insert into age_group_dim values (1, 'young adults (18-35)');
insert into age_group_dim values (2, 'middle-aged adults (36-59)');
insert into age_group_dim values (3, 'old-aged adults (60+)');

-- maint_type_dim
create table maint_type_dim as
select distinct
       maintenancetype,
       maintenancedescription as description
from moncity.maintenancetype;

-- center_dim
create table center_dim as
select distinct
       centerid,
       centername
from moncity.researchcenter;

-- accident_zone_dim: built from the zone values in accidentinfo
create table accident_zone_dim as
select distinct
       accidentzone as zoneid,
       accidentzone
from accidentinfo_clean;

-- error_code_dim
create table error_code_dim as
select distinct
       errorcode,
       errormessage
from moncity.error;

-- severity_dim: built from the severity values in accidentinfo
create table severity_dim as
select distinct
       car_damage_severity as severityid,
       car_damage_severity as cardamageseverity
from accidentinfo_clean;


-- =====================================================================
-- 2. bridge tables
-- =====================================================================

-- team_dim: one row per maintenance team, with the weight factor and
-- a list aggregate of every centre the team belongs to.
-- weightfactor = 1 / number of centres the team belongs to.
create table team_dim as
select teamid,
       1 / count(centerid)                                     as weightfactor,
       listagg(centerid, '_') within group (order by centerid) as centerlist
from moncity.belongto
group by teamid;

-- team_center_bridge: a team can belong to many research centres
create table team_center_bridge as
select distinct teamid, centerid
from moncity.belongto;

-- accident_dim: one row per accident, with the weight factor and
-- a list aggregate of every car involved in the accident.
-- weightfactor = 1 / number of cars in the accident.
create table accident_dim as
select accidentid,
       1 / count(registrationno)                                           as weightfactor,
       listagg(registrationno, '_') within group (order by registrationno) as carlist
from caraccident_clean
group by accidentid;

-- car_accident_bridge: an accident can involve many cars
create table car_accident_bridge as
select distinct accidentid, registrationno
from caraccident_clean;


-- =====================================================================
-- 3. fact tables
-- =====================================================================

-- booking_fact: the age group is decided from the passenger's age when loaded
create table booking_fact as
select to_char(b.bookingdate, 'yyyymm')  as timeid,
       b.registrationno,
       case
           when p.passengerage <= 35 then 1
           when p.passengerage <= 59 then 2
           else 3
       end                               as agegroupid,
       p.facultyid,
       count(distinct b.bookingid)       as num_bookings
from booking_clean b, passenger_clean p
where b.passengerid = p.passengerid
group by to_char(b.bookingdate, 'yyyymm'),
         b.registrationno,
         case
             when p.passengerage <= 35 then 1
             when p.passengerage <= 59 then 2
             else 3
         end,
         p.facultyid;

-- maintenance_fact
create table maintenance_fact as
select to_char(m.maintenancedate, 'yyyymm') as timeid,
       m.registrationno,
       m.maintenancetype,
       m.teamid,
       sum(m.maintenancecost)               as total_cost,
       count(distinct m.maintenanceid)      as num_maintenance
from maintenance_clean m
group by to_char(m.maintenancedate, 'yyyymm'),
         m.registrationno,
         m.maintenancetype,
         m.teamid;

-- accident_fact: one row per accident, cars are reached through the bridge
create table accident_fact as
select a.accidentid,
       a.accidentzone                 as zoneid,
       a.errorcode,
       a.car_damage_severity          as severityid,
       count(distinct a.accidentid)   as num_accidents
from accidentinfo_clean a
group by a.accidentid,
         a.accidentzone,
         a.errorcode,
         a.car_damage_severity;

commit;


-- =====================================================================
-- 4. example queries
-- =====================================================================

-- bookings by it faculty passengers in july using a bus
select sum(f.num_bookings) as num_bookings
from booking_fact f, faculty_dim fd, time_dim t, car_dim c
where f.facultyid = fd.facultyid
  and f.timeid = t.timeid
  and f.registrationno = c.registrationno
  and fd.facultyname = 'IT'
  and t.month = 7
  and lower(c.carbodytype) = 'bus';

-- maintenance records with at least one team from research centre ce04
select sum(f.num_maintenance) as num_maintenance
from maintenance_fact f, team_center_bridge b
where f.teamid = b.teamid
  and b.centerid = 'CE04';

-- accidents in zonea involving car01 (no weight factor when filtering one car)
select sum(f.num_accidents) as num_accidents
from accident_fact f, car_accident_bridge b
where f.accidentid = b.accidentid
  and f.zoneid = 'ZoneA'
  and b.registrationno = 'Car01';


-- =====================================================================
-- 5. table structures and contents
-- =====================================================================
desc time_dim;
desc car_dim;
desc faculty_dim;
desc age_group_dim;
desc maint_type_dim;
desc center_dim;
desc team_dim;
desc accident_zone_dim;
desc error_code_dim;
desc severity_dim;
desc accident_dim;
desc team_center_bridge;
desc car_accident_bridge;
desc booking_fact;
desc maintenance_fact;
desc accident_fact;

select * from team_dim;
select * from accident_dim;
select count(*) as total_rows from booking_fact;
select count(*) as total_rows from maintenance_fact;
select count(*) as total_rows from accident_fact;
