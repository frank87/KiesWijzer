
.PHONY : start

ALL	:	database.log web


database.log	: kiesWijzer.sql
	psql -f $< > $@

web	:	web.go
	go build web.go

start	: ALL
	./web
	
