use nhs_tariffs
go

/*
TL;DR - The stored procedure calculates tariff on a individual spell basis. It returns a final payment for 1088 of 9999 spells 
	as these are the ones that finished in 2017/2018 and 2018/2019. The final payments are huge because dummy hes data has some
	crazy long spells.

Pre-requisites for running: - 'working' schema and 'result' schema exist
							- run func_HRG_tariffselector.sql
							- import hes data to stage.hes
							- import tariff 17/18 data to stage.APC_1718
							- import tariff 18/19 data to stage.APC_1819	

Output : (table) result.calculated_tariff												
*/
print 'Expand and read full commentary at your own risk'
/*----- Overall Commentary/Assumptions -----
The following stored procedure is the main procedure to be used for calculating the tariff based on tariff tables and HES data. 

My assumption is that in a workplace scenario, this stored procedure would be used to create a table (of the results) for an analyst 
who would have restricted access to the database. I have also assumed this stored procedure would not be run on a regular or frequent basis, 
and so (given limited development time) I have not invested much in flexibility.

In other words, I have assumed that at the point the stored procedure is run:
- the raw HES tables and tariff tables for each year would already be uploaded to the stage area of the database
- the format of these tables would be consistent with the format we have been provided with
- the analyst would not be able to (or need to) specify which tables are being used in the tariff calculation

----- Tariff calculation process (why/how I have calculated tariff by spell rather than episode) -----
According to the "2017/18 and 2018/19 National Tariff Payment System" main document - the NHS primarily use a 'spell-based' tariff system.
A spell is the "total continuous stay of a patient using a Hospital Bed on premises controlled by a Health Care Provider".
	It begins with a patient entering hospital ("admission") and ends with a patient leaving hospital ("discharge"). This means that a
	  spell is defined independently to the period of treatment or care for a particular illness - the treatment period for most illnesses will 
	  involve multiple spells. Also 86% of spells are a single day as most treatments do not involve overnight hospital stays.
A spell is broken up into "episodes" which is the level of detail provided in the HES data. However, HRGs (Healthcare Resource Groups) are assigned
	on a spell-basis - they bundle up all diagnoses and procedures received across all episodes in a spell into a single group, for which we have a
	tariff.

Hence the calculation process involves grouping the HES data to spell level, joining the tariffs based on HRG and then calculating the correct tariff
	type and any duration based additional payments. The following data specific assumptions have been gathered from the NHS data dictionary and the
	"2017/18 and 2018/19 National Tariff Payment System" main document:

	- spell duration is epiend (of the last episode in the spell) minus admidate
	- which tariff year to apply is based on the date of discharge, which here I have taken as epiend of the last episode in the spell 
	- where there is not a consistent admimeth in the dummy HES data, I have taken the admimeth of the first episode of the spell
	- where there is not a consistent classpat in the dummy HES data, I have taken the classpat of the first episode of the spell
	- as trimpoint is HRG specific, calculation of long stay payments are also calculated based on spell duration

----- Comments from sense-checking results -----
Running the stored procedure identifies 9999 spells, of which 1088 ended between "04/01/2017 00:00:00" and "04/01/2018 00:00:00". Hence results are only
	provided for these 1088 spells as tariff data is not available outside this period.
Due to the random nature of the HES dummy data, the spells are unrealistically long. Hence the final payments calculated against the dummy data appear
	unrealistically high but as far I can tell, this is due to large long stay payments being applied rather than a mistake in the coding.
*/ 

if OBJECT_ID('working.usp_HRG_calculatetariff') is not null
	drop proc working.usp_HRG_calculatetariff
go

create proc working.usp_HRG_calculatetariff
as
	exec working.usp_HRG_preprocessing;

	if object_id('working.hes_spell') is not null
		drop table working.hes_spell;

	create table working.hes_spell
	(
		spid int identity,
		spell smallint not null,
		hesid bigint not null,
		HRGcode char(6) not null,
		admiage smallint not null,
		spelstart datetime not null,
		spelend datetime not null,
		speldur int not null,
		admimeth char(2) not null,
		classpat tinyint,
		constraint pk_hes_spell primary key nonclustered (spid),
		index ix_tariff clustered (HRGcode, spelend)
	);

	with CTE
	as
	(
	select
		 spell
		,hesid
		,HRGcode
		,first_value(admiage) over (partition by hesid, spell order by epiorder) as admiage
		,first_value(admidate) over (partition by hesid, spell order by epiorder) as spelstart
		,last_value(epiend) over (partition by hesid, spell order by epiorder rows between unbounded preceding and unbounded following) as spelend
		,first_value(admimeth) over (partition by hesid, spell order by epiorder) as admimeth
		,first_value(classpat) over (partition by hesid, spell order by epiorder) as classpat
	from working.hes_epis
	)
	insert into working.hes_spell
	(spell, hesid, HRGcode, admiage, spelstart, spelend, speldur, admimeth, classpat)
	select distinct
		 spell
		,hesid
		,HRGcode
		,admiage
		,spelstart
		,spelend
		,datediff(dd,spelstart,spelend)
		,admimeth
		,classpat
	from CTE;

	if object_id('result.calculated_tariff') is not null
		drop table result.calculated_tariff;

	create table result.calculated_tariff
	(
		rid int identity,
		spell smallint not null,
		hesid bigint not null,
		final_payment money not null,
		constraint pk_calculated_tariff primary key (rid),
	);

	with CTE
	as
	(
	select
		 hes.spell
		,hes.hesid
		,hes.HRGcode
		,hes.admiage
		,hes.spelstart
		,hes.spelend
		,hes.speldur
		,hes.admimeth
		,hes.classpat
		,trf.trf_outp 
		,trf.trf_dayc 
		,trf.trf_oelec
		,trf.trf_nelec
		,trf.trim_oelec
		,trf.trim_nelec
		,trf.trim_pay
		,trf.ssem_valid
		,trf.ssem_pc 
		,trf.trf_ssem 
	from working.hes_spell as hes
	inner join working.tariff as trf
		on hes.HRGcode = trf.HRGcode and hes.spelend < trf.dt_expire and hes.spelend >= trf.dt_effect -- make sargable (use composite index?)
	)
	insert into result.calculated_tariff
		(spell,hesid,final_payment)
		select
			 spell
			,hesid
			,case working.func_tariffselector(admimeth,admiage,classpat,speldur,ssem_valid)
				when 'daycase' then trf_dayc
				when 'outpatient' then trf_outp
				when 'non-elective' then trf_nelec + ((speldur-trim_nelec)+abs(speldur-trim_nelec))/2*trim_pay -- workaround for getting max(0,speldur-trim_nelec)
				when 'ord-elective' then trf_oelec + ((speldur-trim_oelec)+abs(speldur-trim_oelec))/2*trim_pay -- workaround for getting max(0,speldur-trim_oelec)
				else trf_oelec + ((speldur-trim_oelec)+abs(speldur-trim_oelec))/2*trim_pay
				end
		from CTE;

	drop table working.hes_epis;
	drop table working.tariff;
	drop table working.hes_spell;

go

exec working.usp_HRG_calculatetariff

select * from result.calculated_tariff
