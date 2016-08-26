# KiesWijzer
Crowdsourcing the questions to make a difficult decision.


Installation instructions:
1 - Install postgresql.
2 - login as postgres user. <username> is your build-user:
	$ psql
	> create user <username>
	> alter role <username> with createdb option;
	> exit
3 - login as build-user
	make
4 - start web-server: ./web.go

