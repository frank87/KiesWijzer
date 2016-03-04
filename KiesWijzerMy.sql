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
#- Een dontcare(id) levert de volgende vraag van hetzelfde knooppunt op.
CREATE TABLE `question` (
  `idquestion` INT NOT NULL auto_increment COMMENT '',
  `answer` INT NOT NULL COMMENT '',
  `on_yes` INT NOT NULL COMMENT '',
  `on_no` INT NOT NULL COMMENT '',
  `count_yes` INT NOT NULL COMMENT '',
  `count_no` INT NOT NULL COMMENT '',
  `count_total` INT NOT NULL COMMENT '',
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
	if chance > 0 then
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
	return to_char( question_quality( yes, no, total ), '0.00000' ) || question_id;
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

#- zie boven. Excuses dat yes, no, en dontcare bijna kopieën zijn ;)
CREATE PROCEDURE dontcare(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) RETURNS record
begin
declare node_id bigint;
declare c_sorter text;
	select choice_node, sorter into node_id, c_sorter
	from question_select
	where id = last_question;
	if not found then
		raise exception 'question % not found', last_question;
	end if;
	select start(node_id, c_sorter) into q_type, next_question, next_text;
	update question
	set ( count_total ) =
            ( count_total +1 )
	where id = last_question;
	return;	
end;


ALTER FUNCTION dontcare(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) OWNER TO postgres;

#- De entropie wordt gebruikt om de kwaliteit van de vragen te bepalen.
#- Vragen die op elkaar volgen door "dontcare" kunnen in willekeurige volgorde
#- Daarom komt de vraag eerst die het beste selecteert.
CREATE FUNCTION entropy(count integer, denominator integer) RETURNS real
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
   chance real;
begin
chance := count * 1.0 /  denominator;
if chance > 0 then
	return - chance * ln( chance );
else
	return 0;
end if	;

	end;$$;


ALTER FUNCTION entropy(count integer, denominator integer) OWNER TO postgres;


CREATE FUNCTION no(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
node_id bigint;
begin
	select on_no into node_id
	from question
	where id = last_question;
	if not found then
		raise exception 'question % not found', last_question;
	end if;
	update question
	set ( count_no, count_total) =
            ( count_no + 1, count_total +1)
	where id = last_question;
	select start(node_id) into q_type, next_question, next_text;
	return;
end;$$;


ALTER FUNCTION no(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) OWNER TO postgres;




ALTER FUNCTION question_quality(yes integer, no integer, total integer) OWNER TO postgres;

#- Construeert uit de entropie, en het id een uniek veld. De entopie bepaalt de
#- volgorde, het id zorgt er voor dat stellingen met gelijke entropie ook een
#- sorteerbare volgorde krijgen.
CREATE FUNCTION question_sorter(yes integer, no integer, total integer, question_id bigint) RETURNS text
    LANGUAGE plpgsql
    AS $$begin
	return to_char( question_quality( yes, no, total ), '0.00000' ) || question_id;
end;$$;


ALTER FUNCTION question_sorter(yes integer, no integer, total integer, question_id bigint) OWNER TO postgres;

#- De resultaten-maker. De parameters zijn alleen voor intern gebruik bedoeld.
CREATE FUNCTION start(OUT q_type character, OUT question_id bigint, OUT question_txt text, node_id bigint DEFAULT 1, last_sorter text DEFAULT NULL::text) RETURNS record
    LANGUAGE plpgsql
    AS $$begin
	select id, text into question_id, question_txt
	from question_select
	where choice_node = node_id
	and ( last_sorter is null or sorter < last_sorter )
	order by sorter desc;
	if found then
		q_type = 'Q';
		return;
	end if;
	select id, answer_text into question_id, question_txt
	from choice_node
	where id = node_id;
	if not found then
		raise exception 'Start(%) not found', node_id;
	end if;
	q_type = 'A';
end;$$;


ALTER FUNCTION start(OUT q_type character, OUT question_id bigint, OUT question_txt text, node_id bigint, last_sorter text) OWNER TO postgres;

CREATE FUNCTION yes(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
node_id bigint;
begin
	select on_yes into node_id
	from question
	where id = last_question;
	if not found then
		raise exception 'question % not found', last_question;
	end if;
	update question
	set ( count_yes, count_total) =
            ( count_yes + 1, count_total +1)
	where id = last_question;
	select start(node_id) into q_type, next_question, next_text;
	return;
end;$$;





CREATE SEQUENCE choice_node_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE choice_node_seq OWNER TO postgres;


CREATE SEQUENCE question_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE question_id OWNER TO postgres;



ALTER TABLE question OWNER TO postgres;

#- view die de vragen uit de question-tabel in volgorde zet.
#- De volgorde is zo dat vragen die het meeste ja en nee antwoorden krijgen
#- eerst komen (en dan lieft gelijk verdeeld).

CREATE VIEW question_select AS
 SELECT question.choice_node,
    question.id,
    question.text,
    question_sorter(question.count_yes, question.count_no, question.count_total, question.id) AS sorter
   FROM question
  ORDER BY (question_sorter(question.count_yes, question.count_no, question.count_total, question.id)) DESC;


ALTER TABLE question_select OWNER TO postgres;

#- initiele vulling: het antwoord als alle stellingen je niks kunnen schelen.
COPY choice_node (id, answer_text) FROM stdin;
1	stem niet
\.


#-

ALTER TABLE ONLY choice_node
    ADD CONSTRAINT choice_node_pkey PRIMARY KEY (id);


#-
#- TOC entry 2009 (class 2606 OID 16454)
#- Name: question_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
#-

ALTER TABLE ONLY question
    ADD CONSTRAINT question_pkey PRIMARY KEY (id);


#-
#- TOC entry 2007 (class 1259 OID 16470)
#- Name: fki_question_node; Type: INDEX; Schema: public; Owner: postgres
#-

CREATE INDEX fki_question_node ON question USING btree (choice_node);


#-
#- TOC entry 2011 (class 2606 OID 16460)
#- Name: no_exists; Type: FK CONSTRAINT; Schema: public; Owner: postgres
#-

ALTER TABLE ONLY question
    ADD CONSTRAINT no_exists FOREIGN KEY (on_no) REFERENCES choice_node(id);


#-
#- TOC entry 2012 (class 2606 OID 16465)
#- Name: question_node; Type: FK CONSTRAINT; Schema: public; Owner: postgres
#-

ALTER TABLE ONLY question
    ADD CONSTRAINT question_node FOREIGN KEY (choice_node) REFERENCES choice_node(id);


#-
#- TOC entry 2010 (class 2606 OID 16455)
#- Name: yes_existst; Type: FK CONSTRAINT; Schema: public; Owner: postgres
#-

ALTER TABLE ONLY question
    ADD CONSTRAINT yes_existst FOREIGN KEY (on_yes) REFERENCES choice_node(id);


#-
#- TOC entry 2139 (class 0 OID 0)
#- Dependencies: 5
#- Name: public; Type: ACL; Schema: -; Owner: postgres
#-


