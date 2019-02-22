use nhs_tariffs
go

/*
The following stored procedure is nested within usp_HRG_tariffcalc, and runs at the very start.

It extracts the raw HES and tariff data from the stage schema and creates tables in a format that facilitates the tariff calculation.

The two tables are:
- a clustered HES table with desired data types
- a clustered tariff table combining the 1718 and 1819 data with desired data types, using datetime effective and datetime expired 
	columns to distinguish tariffs between years

Desired data types have been chosen based on guidance in the NHS data dictionary and to minimise size.

Date effect and date expire have been based on guidance included in the "2017/18 and 2018/19 National Tariff Payment System" main document:
	2017/2018 -- Datetime Effective: 01/04/2017 00:00:00 -- Datetime Expired 01/04/2018 00:00:00
	2018/2019 -- Datetime Effective: 01/04/2018 00:00:00 -- Datetime Expired 01/04/2019 00:00:0
*/

if OBJECT_ID('working.usp_HRG_preprocessing') is not null
	drop proc working.usp_HRG_preprocessing
go

create proc working.usp_HRG_preprocessing
as
	set nocount on

	if object_id('working.hes_epis') is not null
		drop table working.hes_epis;

	create table working.hes_epis
	(
	hid int identity,
	spell smallint not null,      -- datatypes and non-nullable flags generated based on data dictionary
	epiorder smallint not null,  
	epistart datetime not null,
	epiend datetime not null,
	epitype tinyint not null,
	sex tinyint not null,
	bedyear smallint not null,
	epidur smallint,
	epistat tinyint not null,
	spellbgin tinyint,
	activage smallint not null,
	admiage smallint not null,
	admincat tinyint not null,
	admincatst tinyint,
	category tinyint,
	dob datetime not null,
	endage smallint,
	ethnos varchar(2) not null,
	hesid bigint not null,
	leglcat tinyint not null,
	lopatid bigint not null,
	newnhsno bigint not null,
	newnhsno_check char(1) not null,
	startage smallint,
	admidate datetime not null,
	admimeth char(2) not null,
	admisorc smallint not null,
	elecdate datetime not null,
	elecdur smallint,
	elecdur_calc smallint,
	classpat tinyint,
	diag_01 varchar(6),
	numepisodesinspell smallint not null,
	HRGcode char(6) not null,
	constraint pk_hes_epis primary key (hid)
	);

	insert into working.hes_epis
	(spell,epiorder,epistart,epiend,epitype,sex,bedyear,epidur,epistat,spellbgin,activage,admiage,admincat,admincatst,category,dob,endage,ethnos,
	hesid,leglcat,lopatid,newnhsno,newnhsno_check,startage,admidate,admimeth,admisorc,elecdate,elecdur,elecdur_calc,classpat,
	diag_01,numepisodesinspell,HRGcode)
	(
	select
		*					-- relying on implicit data conversion
	from stage.hes_hrg
	);

	if object_id('working.tariff') is not null
		drop table working.tariff;

	create table working.tariff
	(
	tid int identity,
	HRGcode char(6) not null,
	dt_effect datetime not null,
	dt_expire datetime not null,
	trf_outp money,
	trf_dayc money,
	trf_oelec money,
	trf_nelec money,
	trim_oelec smallint,
	trim_nelec smallint,
	trim_pay money,
	ssem_valid varchar(3),
	ssem_pc float,
	trf_ssem money,
	constraint pk_tariff primary key (tid)
	);

	insert into working.tariff
	(HRGcode,dt_effect,dt_expire,trf_outp,trf_dayc,trf_oelec,trf_nelec,trim_oelec,trim_nelec,trim_pay,ssem_valid,ssem_pc,trf_ssem)
	(
	select
		 [HRG code]
		,cast('2017-04-01' as datetime)
		,cast('2018-04-01' as datetime)
		,case cast([Outpatient procedure tariff (£)] as varchar(20))
			when '-' then null
			else cast([Outpatient procedure tariff (£)] as money)
		 end
		,case cast([Combined day case   ordinary elective spell tariff (£)] as varchar(20))
			when '-' then cast([Day case spell tariff (£)] as money)
			else cast([Combined day case   ordinary elective spell tariff (£)] as money)
		 end
		,case cast([Combined day case   ordinary elective spell tariff (£)] as varchar(20))
			when '-' then cast([Ordinary elective spell tariff (£)] as money)
			else cast([Combined day case   ordinary elective spell tariff (£)] as money)
		 end
		,cast([Non-elective spell tariff (£)] as money)
		,[Ordinary elective long stay trim point (days)]
		,[Non-elective long stay trim point (days)]
		,[Per day long stay payment (for days exceeding trim point) (£)]
		,[Reduced short stay emergency tariff  applicable?]
		,case [Reduced short stay emergency tariff  applicable?]
			when 'no' then null
			else cast(replace(cast([% applied in calculation of reduced short stay emergency tariff ] as varchar(10)),'%','') as float)/100
		 end
		,case [Reduced short stay emergency tariff  applicable?]
			when 'no' then null
			else cast([Reduced short stay emergency tariff (£)] as money)
		 end
	from stage.APC_1718
	UNION ALL -- assuming that tariff tables will always have distinct data rows
	select
		 [HRG code]
		,cast('2018-04-01' as datetime)
		,cast('2019-04-01' as datetime)
		,case cast([Outpatient procedure tariff (£)] as varchar(20))
			when '-' then null
			else cast([Outpatient procedure tariff (£)] as money)
		 end
		,case cast([Combined day case   ordinary elective spell tariff (£)] as varchar(20))
			when '-' then 1--cast([Day case spell tariff (£)] as money)
			else cast([Combined day case   ordinary elective spell tariff (£)] as money)
		 end
		,case cast([Combined day case   ordinary elective spell tariff (£)] as varchar(20))
			when '-' then cast([Ordinary elective spell tariff (£)] as money)
			else cast([Combined day case   ordinary elective spell tariff (£)] as money)
		 end
		,cast([Non-elective spell tariff (£)] as money)
		,[Ordinary elective long stay trim point (days)]
		,[Non-elective long stay trim point (days)]
		,[Per day long stay payment (for days exceeding trim point) (£)]
		,[Reduced short stay emergency tariff  applicable?]
		,case [Reduced short stay emergency tariff  applicable?]
			when 'no' then null
			else cast(replace(cast([% applied in calculation of reduced short stay emergency tariff ] as varchar(10)),'%','') as float)/100
		 end
		,case [Reduced short stay emergency tariff  applicable?]
			when 'no' then null
			else cast([Reduced short stay emergency tariff (£)] as money)
		end
	from stage.APC_1819
	);
go
