# KiesWijzer
Crowdsourcing the questions to make a difficult decision.


Installation instructions:
1 - Install postgresql.
2 - as postgres <username> is your build-user:
	$ psql
	> create user <username>
	> alter role <username> with createdb option;
	> exit
3 - as build-user
	make


