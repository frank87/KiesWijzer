

ALL	:	database.log


database.log	: kiesWijzer.sql
	psql -f $< > $@

