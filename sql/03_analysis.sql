-- =====================================================================
-- moncity data warehouse
-- 03. data analysis
--
-- olap and analytics techniques used:
--   joins written as from a, b where a.x = b.x (lab 09a style)
--   group by rollup / cube with decode(grouping(...)) (lab 09a part a)
--   rank / dense_rank / percent_rank over (...) (lab 09a part b)
--   cumulative and moving aggregates over (... rows ...) (lab 09a part c)
--   simple linear regression slope and intercept (lab 10)
--   to_char(..., '9,999,999.99') for formatting (lab 09a part c)
-- =====================================================================


-- ---------------------------------------------------------------------
-- a1. car body type comparison (the main investment question)
--     three separate queries, one per fact table, so rows never multiply.
--     each divides by the number of cars of that body type, so body
--     types with bigger fleets don't look better just by size.
-- ---------------------------------------------------------------------

-- a1a. bookings per body type, and per car
select c.carbodytype,
       c.numseats,
       fl.num_cars,
       sum(f.num_bookings) as num_bookings,
       to_char(sum(f.num_bookings) / fl.num_cars, '9,990.99') as bookings_per_car
from booking_fact f, car_dim c,
     (select carbodytype, numseats, count(*) as num_cars
      from car_dim
      group by carbodytype, numseats) fl
where f.registrationno = c.registrationno
and c.carbodytype = fl.carbodytype
and c.numseats = fl.numseats
group by c.carbodytype, c.numseats, fl.num_cars
order by c.carbodytype, c.numseats;

-- a1b. maintenance records and cost per body type, and per car
select c.carbodytype,
       c.numseats,
       fl.num_cars,
       sum(f.num_maintenance) as num_maintenance,
       sum(f.total_cost)      as total_cost,
       to_char(sum(f.total_cost) / fl.num_cars, '9,999,990.99') as cost_per_car
from maintenance_fact f, car_dim c,
     (select carbodytype, numseats, count(*) as num_cars
      from car_dim
      group by carbodytype, numseats) fl
where f.registrationno = c.registrationno
and c.carbodytype = fl.carbodytype
and c.numseats = fl.numseats
group by c.carbodytype, c.numseats, fl.num_cars
order by c.carbodytype, c.numseats;

-- a1c. accidents per body type, and per car (through the bridge)
select c.carbodytype,
       c.numseats,
       fl.num_cars,
       count(distinct f.accidentid) as num_accidents,
       to_char(count(distinct f.accidentid) / fl.num_cars, '9,990.99') as accidents_per_car
from accident_fact f, car_accident_bridge b, car_dim c,
     (select carbodytype, numseats, count(*) as num_cars
      from car_dim
      group by carbodytype, numseats) fl
where f.accidentid = b.accidentid
and b.registrationno = c.registrationno
and c.carbodytype = fl.carbodytype
and c.numseats = fl.numseats
group by c.carbodytype, c.numseats, fl.num_cars
order by c.carbodytype, c.numseats;


-- ---------------------------------------------------------------------
-- a2. rollup: bookings by body type and age group, with subtotals
-- ---------------------------------------------------------------------
select decode(grouping(c.carbodytype), 1, 'All Body Types', c.carbodytype) as body_type,
       decode(grouping(a.agegroupdesc), 1, 'All Age Groups', a.agegroupdesc) as age_group,
       sum(f.num_bookings) as num_bookings
from booking_fact f, car_dim c, age_group_dim a
where f.registrationno = c.registrationno
and f.agegroupid = a.agegroupid
group by rollup (c.carbodytype, a.agegroupdesc)
order by c.carbodytype, a.agegroupdesc;


-- ---------------------------------------------------------------------
-- a3. cube: accidents by zone and severity, with all subtotals
-- ---------------------------------------------------------------------
select decode(grouping(z.accidentzone), 1, 'All Zones', z.accidentzone) as zone,
       decode(grouping(s.cardamageseverity), 1, 'All Severities', s.cardamageseverity) as severity,
       sum(f.num_accidents) as num_accidents
from accident_fact f, accident_zone_dim z, severity_dim s
where f.zoneid = z.zoneid
and f.severityid = s.severityid
group by cube (z.accidentzone, s.cardamageseverity)
order by z.accidentzone, s.cardamageseverity;


-- ---------------------------------------------------------------------
-- a4. rank: error codes by number of accidents
-- ---------------------------------------------------------------------
select e.errorcode,
       e.errormessage,
       sum(f.num_accidents) as num_accidents,
       rank() over (order by sum(f.num_accidents) desc) as accident_rank
from accident_fact f, error_code_dim e
where f.errorcode = e.errorcode
group by e.errorcode, e.errormessage
order by accident_rank;


-- ---------------------------------------------------------------------
-- a5. dense_rank: cars with the most accidents (top 10 ranks)
-- ---------------------------------------------------------------------
select registrationno, carbodytype, num_accidents, accident_rank
from (select b.registrationno,
             c.carbodytype,
             count(distinct f.accidentid) as num_accidents,
             dense_rank() over (order by count(distinct f.accidentid) desc) as accident_rank
      from accident_fact f, car_accident_bridge b, car_dim c
      where f.accidentid = b.accidentid
      and b.registrationno = c.registrationno
      group by b.registrationno, c.carbodytype)
where accident_rank <= 10
order by accident_rank;


-- ---------------------------------------------------------------------
-- a6. rollup: maintenance cost by maintenance type and body type
-- ---------------------------------------------------------------------
select decode(grouping(mt.description), 1, 'All Maintenance Types', mt.description) as maintenance_type,
       decode(grouping(c.carbodytype), 1, 'All Body Types', c.carbodytype) as body_type,
       sum(f.num_maintenance) as num_maintenance,
       sum(f.total_cost)      as total_cost
from maintenance_fact f, maint_type_dim mt, car_dim c
where f.maintenancetype = mt.maintenancetype
and f.registrationno = c.registrationno
group by rollup (mt.description, c.carbodytype)
order by mt.description, c.carbodytype;


-- ---------------------------------------------------------------------
-- a7. rank: maintenance cost by research centre
--     the weight factor stops a team's cost being counted once per centre
-- ---------------------------------------------------------------------
select c.centerid,
       c.centername,
       to_char(sum(f.total_cost * t.weightfactor), '9,999,999.99') as weighted_cost,
       rank() over (order by sum(f.total_cost * t.weightfactor) desc) as cost_rank
from maintenance_fact f, team_dim t, team_center_bridge br, center_dim c
where f.teamid = t.teamid
and t.teamid = br.teamid
and br.centerid = c.centerid
group by c.centerid, c.centername
order by cost_rank;


-- ---------------------------------------------------------------------
-- a8. cumulative bookings and 3-month moving average over time
-- ---------------------------------------------------------------------
select f.timeid,
       sum(f.num_bookings) as num_bookings,
       sum(sum(f.num_bookings)) over (order by f.timeid rows unbounded preceding) as cumulative_bookings,
       to_char(avg(sum(f.num_bookings)) over (order by f.timeid rows 2 preceding), '9,999.99') as moving_3_month_avg
from booking_fact f
group by f.timeid
order by f.timeid;


-- ---------------------------------------------------------------------
-- a9. percent_rank: months in the top 25% for maintenance cost
-- ---------------------------------------------------------------------
select timeid, total_cost, pct_rank
from (select f.timeid,
             sum(f.total_cost) as total_cost,
             percent_rank() over (order by sum(f.total_cost)) as pct_rank
      from maintenance_fact f
      group by f.timeid)
where pct_rank >= 0.75
order by pct_rank desc;


-- ---------------------------------------------------------------------
-- a10. linear regression: is booking demand growing over time?
--      x = month number in sequence (1, 2, 3, ...) from row_number()
--      y = bookings in that month
--      positive slope = demand is growing each month
-- ---------------------------------------------------------------------
select slope,
       y_bar_max - x_bar_max * slope as intercept
from (
    select sum((x - x_bar) * (y - y_bar)) / sum((x - x_bar) * (x - x_bar)) as slope,
           max(x_bar) as x_bar_max,
           max(y_bar) as y_bar_max
    from (
        select x, avg(x) over () as x_bar,
               y, avg(y) over () as y_bar
        from (
            select row_number() over (order by f.timeid) as x,
                   sum(f.num_bookings) as y
            from booking_fact f
            group by f.timeid)
        ) s
);


-- ---------------------------------------------------------------------
-- a11. linear regression: do older cars have more accidents?
--      x = manufacturing year, y = number of accidents for that car
--      negative slope = older cars (lower year) have more accidents
--      cars with no accidents are included with y = 0, so the line isn't biased
-- ---------------------------------------------------------------------
select slope,
       y_bar_max - x_bar_max * slope as intercept
from (
    select sum((x - x_bar) * (y - y_bar)) / sum((x - x_bar) * (x - x_bar)) as slope,
           max(x_bar) as x_bar_max,
           max(y_bar) as y_bar_max
    from (
        select x, avg(x) over () as x_bar,
               y, avg(y) over () as y_bar
        from (
            select c.registrationno,
                   c.manufacturingyear as x,
                   (select count(distinct b.accidentid)
                    from car_accident_bridge b
                    where b.registrationno = c.registrationno) as y
            from moncity.car c)
        ) s
);
