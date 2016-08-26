#-------------------------------------------------------------------------------
#- Kieswijzer geinspireerd op het programma 'animal'. Met user-generated 
#- stellingen
#-
#- Belangrijkste functies voor de user-interface: 
#- start() 
#-   geeft terug: 
#-	resultaat-type ('Q' -> stelling, 'A' -> advies )
#-	id (getal voor verder gebruik, afhankelijk van het resultaat-type )
#-	tekst ( van de stelling, dan wel het advies )
#-
#- Bij een resultaat van het type 'Q' kun je de volgende functies gebruiken:
#-	yes(id) -> Eens
#-	no(id) -> oneens
#-	dontcare(id) -> weet niet/geen mening/stomme vraag
#- Deze hebben allemaal dezelfde resultaatvelden als start()
#-
#- Als het resultaat het type 'A' heeft, kun je de volgende functie gebruiken
#- om een stelling in de boom toe te voegen:
#-	add_question(id, antwoord, stelling)
#- Hierin is 
#-	- id -> het resultaat als hierboven.
#- 	- antwoord -> de mening van de gebruiker
#-	- stelling -> een stelling waarmee de gebruiker de mensen kan 
#-		overtuigen om dit advies te geven in plaats van het advies dat 
#-		hij gekregen heeft.
#-
#-------------------------------------------------------------------------------


#- zie uitleg boven

#- knooppunten als in het beroemde programma "animal" (uit 1970 of 1980).
#- met het verschil dat ieder knooppunt 1 antwoord, en mogelijk meerdere vragen
#- bevat (de verwijzingen staan bij de vragen)
create schema `KiesWijzer`;
use `KiesWijzer`; 

CREATE TABLE `answer` (
  `idanswer` INT NOT NULL auto_increment COMMENT '',
  `answertext` VARCHAR(45) NULL COMMENT '',
  PRIMARY KEY (`idanswer`)  COMMENT '');

# het systeem heeft 1 eerste antwoord nodig
INSERT INTO `answer` ( idanswer, answertext ) values ( 1, 'stem niet' );

#- De vragentabel met verwijzing naar het volgende knooppunt.
# Een dontcare(id) levert de volgende vraag van hetzelfde knooppunt op.
CREATE TABLE `question` (
  `idquestion` INT NOT NULL auto_increment COMMENT '',
  `answer` INT NOT NULL COMMENT '',
  `on_yes` INT NOT NULL COMMENT '',
  `on_no` INT NOT NULL COMMENT '',
  `count_yes` INT NOT NULL default 1 COMMENT '',
  `count_no` INT NOT NULL default 0 COMMENT '',
  `count_total` INT NOT NULL default 1 COMMENT '',
  `text` varchar(200),
  PRIMARY KEY (`idquestion`)  COMMENT '',
  CONSTRAINT `fk_question_1`
    FOREIGN KEY (`answer`)
    REFERENCES `answer` (`idanswer`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_question_2`
    FOREIGN KEY (`on_yes`)
    REFERENCES `answer` (`idanswer`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_question_3`
    FOREIGN KEY (`on_no`)
    REFERENCES `answer` (`idanswer`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION );

DELIMITER --end--

CREATE PROCEDURE `add_question`(choice_node_id int, yes_answer text, q_text text)
begin
declare no_answer varchar(45);
declare yes_id, no_id int;
insert into answer ( answertext ) values ( yes_answer );
set yes_id =  LAST_INSERT_ID();
insert into answer ( answertext ) select answertext from answer a where a.idanswer = choice_node_id;
set no_id = LAST_INSERT_ID();
insert into question (answer, text, on_yes, on_no ) values ( choice_node_id, q_text, yes_id, no_id );
end;

--end--

CREATE FUNCTION `entropy`(count integer, denominator integer) RETURNS double
begin
	declare chance real;
	set chance := count * 1.0 /  denominator;
	if chance > 0.001 then
        return - chance * ln( chance );
	else
        return 0;
	end if;
end;
--end--
#- bepaalt de entropie op basis van de antwoorden (het aantal yes/no/dontcare)
CREATE FUNCTION question_quality(yes integer, no integer, total integer) RETURNS real
begin
	return( entropy(yes,total) + entropy(no,total) );
end;
--end--
#- Construeert uit de entropie, en het id een uniek veld. De entopie bepaalt de
#- volgorde, het id zorgt er voor dat stellingen met gelijke entropie ook een
#- sorteerbare volgorde krijgen.
CREATE FUNCTION question_sorter(yes integer, no integer, total integer, question_id int) RETURNS text
begin
	return concat( format( question_quality( yes, no, total ), 4 ), question_id);
end;
--end--
#- view die de vragen uit de question-tabel in volgorde zet.
#- De volgorde is zo dat vragen die het meeste ja en nee antwoorden krijgen
#- eerst komen (en dan lieft gelijk verdeeld).

CREATE VIEW question_select AS
 SELECT question.answer,
    question.idquestion,
    question.text,
    question_sorter(question.count_yes, question.count_no, question.count_total, question.idquestion) AS sorter
   FROM question
  ORDER BY sorter DESC;
--end--
#- De resultaten-maker. De parameters zijn alleen voor intern gebruik bedoeld.
create procedure start( node_id int, last_sorter text )
	select 1, idquestion, text, sorter
	from  question_select
	where answer = node_id
	and   ( last_sorter is null or sorter < last_sorter ) 
	union
	select 2, idanswer, answertext, 'xxxx'
	from answer
	where idanswer = node_id
	order by 1, 4 desc;
--end--

#- zie boven. Excuses dat yes, no, en dontcare bijna kopieën zijn ;)
CREATE PROCEDURE dontcare(last_question bigint)
begin
declare node_id bigint;
declare c_sorter text;
	select answer, sorter into node_id, c_sorter
	from question_select
	where idquestion = last_question;
	call start(node_id, c_sorter);
	update question
	set count_total = count_total +1 
	where id = last_question;
end;
--end--
CREATE PROCEDURE yes(last_question bigint)
begin
declare node_id bigint;
	select on_yes into node_id
	from question
	where idquestion = last_question;
	call start(node_id, NULL);
	update question
	set count_total = count_total + 1,
		count_yes = count_yes +1
	where id = last_question;
end;
--end--
CREATE PROCEDURE no(last_question bigint)
begin
declare node_id bigint;
	select on_no into node_id
	from question
	where idquestion = last_question;
	call start(node_id, NULL);
	update question
	set count_total = count_total + 1,
		count_no = count_no +1
	where id = last_question;
end;
--end--
create procedure previous(last_answer int)
begin
select answer, 'voor', text from question where on_yes = last_answer
union
select answer, 'tegen', text from question where on_no = last_answer;
end;
--end--