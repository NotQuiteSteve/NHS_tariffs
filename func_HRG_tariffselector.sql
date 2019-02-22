use nhs_tariffs
go

/*
The following function determines if a spell is Ordinary Elective, Non-elective, day case, outpatient or short stay emergency.
The function is called from within usp_HRG_tariffcalculation

The following definitions have been used:
1) Short Stay Emergency (SSEM)
	-  patients length of stay is either zero or one day (54a)
	-  patient is under 19 on date of admission (54b)
	-  admission method code is in (21-25, 28, 2A, 2B, 2C ,2D) (54c)
	-  ssem is applicable to the HRG code (54d)
	(note 54e is not possible with HES dummy data)
2) Non-elective
	-  admission method code is in (21-25, 28, 2A, 2B, 2C ,2D)
	-  spell is not an SSEM
3) Day case
	-  admission method code is in (11,12,13)
	-  spell begins and ends on the same day
	-  patient class is 'Day case admission' (classpat = 2)
3) Outpatient 
	-  admission method code is in (11,12,13)
	-  spell begins and ends on the same day
	-  patient class is NOT 'Day case admission' (classpat != 2)
4) Ordinary Elective
	-  admission method code is in (11,12,13)
	-  spell is not an day case or outpatient
5) Other
	-  spells that do not correspond to 4 definitions above
	*/

if object_id('working.func_tariffselector') is not null
	drop function working.func_tariffselector
go
	
create function working.func_tariffselector (@admimeth varchar(2),@admiage tinyint,@classpat tinyint,@speldur smallint, @ssem_valid varchar(3))
returns varchar(20)
As
begin
	declare @flag_emerg bit;
	declare @flag_planned bit;
	declare @flag_under19 bit;
	declare @flag_under2days bit;
	declare @flag_sameday bit;
	declare @flag_daycase bit;
	declare @flag_ssemvalid bit;
	declare @return varchar(20);

	if @admimeth in ('21','22','23','24','25','2A','2B','2C','2D','28') set @flag_emerg = 1 else set @flag_emerg = 0;
	if @admimeth in ('11','12','13') set @flag_planned = 1 else set @flag_planned = 0;
	if @admiage <19 set @flag_under19 = 1 else set @flag_under19 = 0;
	if @ssem_valid = 'Yes' set @flag_ssemvalid = 1 else set @flag_ssemvalid = 0;
	if @speldur <2 set @flag_under2days = 1 else set @flag_under2days = 0;
	if @speldur = 0 set @flag_sameday = 1 else set @flag_sameday = 0;
	if @classpat = 2 set @flag_daycase = 1 else set @flag_daycase = 0;

	if @flag_emerg=1 and @flag_under19=1 and @flag_under2days=1 and @flag_ssemvalid=1 set @return = 'ssem'
	else if @flag_emerg=1 set @return = 'non-elective'
	else if @flag_planned=1 and @flag_sameday=1 and @flag_daycase=1 set @return = 'daycase'
	else if @flag_planned=1 and @flag_sameday=1 set @return = 'outpatient'
	else if @flag_planned=1 set @return = 'ord-elective'
	else set @return = 'other'

	return(@return);
end;
go