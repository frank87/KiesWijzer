--------------------------------------------------------------------------------
-- Kieswijzer geinspireerd op het programma 'animal'. Met user-generated 
-- stellingen
--
-- Belangrijkste functies voor de user-interface: 
-- start() 
--   geeft terug: 
--	resultaat-type ('Q' -> stelling, 'A' -> advies )
--	id (getal voor verder gebruik, afhankelijk van het resultaat-type )
--	tekst ( van de stelling, dan wel het advies )
--
-- Bij een resultaat van het type 'Q' kun je de volgende functies gebruiken:
--	yes(id) -> Eens
--	no(id) -> oneens
--	dontcare(id) -> weet niet/geen mening/stomme vraag
-- Deze hebben allemaal dezelfde resultaatvelden als start()
--
-- Als het resultaat het type 'A' heeft, kun je de volgende functie gebruiken
-- om een stelling in de boom toe te voegen:
--	add_question(id, antwoord, stelling)
-- Hierin is 
--	- id -> het resultaat als hierboven.
-- 	- antwoord -> de mening van de gebruiker
--	- stelling -> een stelling waarmee de gebruiker de mensen kan 
--		overtuigen om dit advies te geven in plaats van het advies dat 
--		hij gekregen heeft.
--
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Automatisch gegenereerde zooi, voor het programma zie verder...
--------------------------------------------------------------------------------
\set ON_ERROR_STOP on
SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

DROP DATABASE "kiesWijzer";
CREATE DATABASE "kiesWijzer" WITH TEMPLATE = template0;


-- ALTER DATABASE "kiesWijzer" OWNER TO postgres;

\connect "kiesWijzer"

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;


COMMENT ON DATABASE "kiesWijzer" IS 'Database achter de neutraalste kieswijzen van Nederland';



CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';

SET search_path = public, pg_catalog;

--------------------------------------------------------------------------------
-- Eigen werk.
--
-- 
--------------------------------------------------------------------------------

-- zie uitleg boven
CREATE FUNCTION add_question(choice_node_id bigint, yes_answer text, q_text text) RETURNS void
    LANGUAGE plpgsql
    AS $$declare
yes_node bigint;
no_node bigint;
no_answer text;
begin
no_node = nextval('choice_node_seq');
yes_node = nextval('choice_node_seq');
select a.answer_text into no_answer from choice_node a where a.id = choice_node_id;
insert into choice_node (id, answer_text) values (no_node, no_answer );
insert into choice_node (id, answer_text) values (yes_node, yes_answer );
insert into question (choice_node, text, on_yes, on_no ) values ( choice_node_id, q_text, yes_node, no_node );
end;
$$;


ALTER FUNCTION add_question(choice_node_id bigint, yes_answer text, q_text text) OWNER TO postgres;


-- zie boven. Excuses dat yes, no, en dontcare bijna kopieën zijn ;)
CREATE FUNCTION dontcare(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
node_id bigint;
c_sorter text;
begin
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
end;$$;


ALTER FUNCTION dontcare(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) OWNER TO postgres;

-- De entropie wordt gebruikt om de kwaliteit van de vragen te bepalen.
-- Vragen die op elkaar volgen door "dontcare" kunnen in willekeurige volgorde
-- Daarom komt de vraag eerst die het beste selecteert.
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

-- bepaalt de entropie op basis van de antwoorden (het aantal yes/no/dontcare)
CREATE FUNCTION question_quality(yes integer, no integer, total integer) RETURNS real
    LANGUAGE plpgsql
    AS $$begin
	return( entropy(yes,total) + entropy(no,total) );
end;$$;


ALTER FUNCTION question_quality(yes integer, no integer, total integer) OWNER TO postgres;

-- Construeert uit de entropie, en het id een uniek veld. De entopie bepaalt de
-- volgorde, het id zorgt er voor dat stellingen met gelijke entropie ook een
-- sorteerbare volgorde krijgen.
CREATE FUNCTION question_sorter(yes integer, no integer, total integer, question_id bigint) RETURNS text
    LANGUAGE plpgsql
    AS $$begin
	return to_char( question_quality( yes, no, total ), '0.00000' ) || question_id;
end;$$;


ALTER FUNCTION question_sorter(yes integer, no integer, total integer, question_id bigint) OWNER TO postgres;

-- De resultaten-maker. De parameters zijn alleen voor intern gebruik bedoeld.
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


ALTER FUNCTION yes(OUT q_type character, OUT next_question bigint, OUT next_text text, last_question bigint) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

-- knooppunten als in het beroemde programma "animal" (uit 1970).
-- met het verschil dat ieder knooppunt 1 antwoord, en mogelijk meerdere vragen
-- bevat (de verwijzingen staan bij de vragen)

CREATE TABLE choice_node (
    id bigint NOT NULL,
    answer_text text
);


ALTER TABLE choice_node OWNER TO postgres;


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

-- De vragentabel met verwijzing naar het volgende knooppunt.
-- Een dontcare(id) levert de volgende vraag van hetzelfde knooppunt op.

CREATE TABLE question (
    id bigint DEFAULT nextval('question_id'::regclass) NOT NULL,
    text text,
    on_yes bigint,
    on_no bigint,
    count_yes integer DEFAULT 1,
    count_no integer DEFAULT 0,
    count_total integer DEFAULT 1,
    choice_node bigint
);


ALTER TABLE question OWNER TO postgres;

-- view die de vragen uit de question-tabel in volgorde zet.
-- De volgorde is zo dat vragen die het meeste ja en nee antwoorden krijgen
-- eerst komen (en dan lieft gelijk verdeeld).

CREATE VIEW question_select AS
 SELECT question.choice_node,
    question.id,
    question.text,
    question_sorter(question.count_yes, question.count_no, question.count_total, question.id) AS sorter
   FROM question
  ORDER BY (question_sorter(question.count_yes, question.count_no, question.count_total, question.id)) DESC;


ALTER TABLE question_select OWNER TO postgres;

-- initiele vulling: het antwoord als alle stellingen je niks kunnen schelen.
COPY choice_node (id, answer_text) FROM stdin;
1	stem niet
\.


--

ALTER TABLE ONLY choice_node
    ADD CONSTRAINT choice_node_pkey PRIMARY KEY (id);


--
-- TOC entry 2009 (class 2606 OID 16454)
-- Name: question_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY question
    ADD CONSTRAINT question_pkey PRIMARY KEY (id);


--
-- TOC entry 2007 (class 1259 OID 16470)
-- Name: fki_question_node; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fki_question_node ON question USING btree (choice_node);


--
-- TOC entry 2011 (class 2606 OID 16460)
-- Name: no_exists; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY question
    ADD CONSTRAINT no_exists FOREIGN KEY (on_no) REFERENCES choice_node(id);


--
-- TOC entry 2012 (class 2606 OID 16465)
-- Name: question_node; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY question
    ADD CONSTRAINT question_node FOREIGN KEY (choice_node) REFERENCES choice_node(id);


--
-- TOC entry 2010 (class 2606 OID 16455)
-- Name: yes_existst; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY question
    ADD CONSTRAINT yes_existst FOREIGN KEY (on_yes) REFERENCES choice_node(id);


--
-- TOC entry 2139 (class 0 OID 0)
-- Dependencies: 5
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--


